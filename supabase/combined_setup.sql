-- =============================================================================
-- combined_setup.sql - Ramprasad Defence full database setup.
-- Generated from supabase/migrations/*.sql (in order) + supabase/seed/0001_roles.sql.
-- Paste this whole file into Supabase Dashboard > SQL Editor and click Run.
-- Run it ONCE on a new/empty project. Safe order: policies reference Supabase roles.
-- =============================================================================

-- ============================== 0001_foundation.sql ==============================
-- =============================================================================
-- 0001_foundation.sql
-- Ramprasad Defence - Defence Contract & Supply Management System
-- Schema foundation: helper schema, generic trigger functions.
-- No business tables here. Safe to run first.
-- =============================================================================

create schema if not exists app;

comment on schema app is
  'Internal helper schema: security helpers and generic trigger functions. Not a data schema; no business tables.';

-- -----------------------------------------------------------------------------
-- updated_at maintenance
-- Attached to every table that has an updated_at column (see 0012_triggers.sql).
-- -----------------------------------------------------------------------------
create or replace function app.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function app.set_updated_at() is
  'Trigger function: sets NEW.updated_at = now() on every UPDATE.';

-- -----------------------------------------------------------------------------
-- Generic parent-total recalculation
-- Recomputes subtotal / tax_total / grand_total on a parent header row from its
-- child line items. Child tables must expose the standard money columns:
--   quantity, unit_price, discount_pct, line_total
-- Trigger arguments: (parent_table, foreign_key_column_of_child)
-- The trigger function is SECURITY DEFINER so it can update the parent even when
-- the caller would not otherwise be allowed to write the header.
-- -----------------------------------------------------------------------------
create or replace function app.recalc_parent_totals()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_parent_table text := tg_argv[0];
  v_fk           text := tg_argv[1];
  v_id           uuid;
begin
  if (tg_op = 'DELETE') then
    v_id := (to_jsonb(old) ->> v_fk)::uuid;
  else
    v_id := (to_jsonb(new) ->> v_fk)::uuid;
  end if;

  if (v_id is null) then
    return null;
  end if;

  -- Recompute from the surviving child rows for this parent.
  execute format(
    $f$
      update public.%I p
         set subtotal    = coalesce(a.sub, 0),
             tax_total   = coalesce(a.grand, 0) - coalesce(a.sub, 0),
             grand_total = coalesce(a.grand, 0),
             updated_at  = now()
        from (
              select sum(round(quantity * unit_price * (1 - discount_pct / 100), 2)) as sub,
                     sum(line_total) as grand
                from public.%I
               where %I = $1
             ) a
       where p.id = $1
    $f$, v_parent_table, tg_table_name, v_fk
  ) using v_id;

  -- If the parent no longer has any children, zero the totals.
  execute format(
    $f$
      update public.%I p
         set subtotal = 0, tax_total = 0, grand_total = 0, updated_at = now()
       where p.id = $1
         and not exists (select 1 from public.%I c where c.%I = p.id)
    $f$, v_parent_table, tg_table_name, v_fk
  ) using v_id;

  return null;
end;
$$;

comment on function app.recalc_parent_totals() is
  'Trigger function: recalculates subtotal/tax_total/grand_total on a parent header from its child lines. Args: (parent_table, child_fk_column).';

-- -----------------------------------------------------------------------------
-- Generic append-only audit trigger
-- Writes one audit_logs row per insert/update/delete. SECURITY DEFINER so the
-- audit row can be written even though audit_logs has no INSERT policy for
-- normal roles. Attached to business tables in 0012_triggers.sql.
-- Depends on public.audit_logs (created in 0010_ops.sql) and app.current_user_id()
-- (created in 0003_security_helpers.sql) at run time, not at creation time.
-- -----------------------------------------------------------------------------
create or replace function app.audit_row()
returns trigger
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_actor  uuid;
  v_action text;
  v_before jsonb;
  v_after  jsonb;
  v_entity uuid;
begin
  v_actor := app.current_user_id();

  if (tg_op = 'INSERT') then
    v_action := 'insert';
    v_after  := to_jsonb(new);
  elsif (tg_op = 'UPDATE') then
    v_action := 'update';
    v_before := to_jsonb(old);
    v_after  := to_jsonb(new);
  elsif (tg_op = 'DELETE') then
    v_action := 'delete';
    v_before := to_jsonb(old);
  else
    return null;
  end if;

  begin
    v_entity := coalesce((v_after ->> 'id')::uuid, (v_before ->> 'id')::uuid);
  exception when others then
    v_entity := null;
  end;

  insert into public.audit_logs (actor_user_id, action, entity_table, entity_id, before_data, after_data)
  values (v_actor, v_action, tg_table_name, v_entity, v_before, v_after);

  if (tg_op = 'DELETE') then
    return old;
  end if;
  return new;
end;
$$;

comment on function app.audit_row() is
  'Trigger function: writes an append-only audit_logs row for insert/update/delete on any business table.';

-- ============================== 0002_identity.sql ==============================
-- =============================================================================
-- 0002_identity.sql
-- Identity and access: users, roles, user_roles.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- users
-- Our own user record. id is OUR identifier (referenced by every audit column),
-- auth_user_id mirrors the Supabase auth.users id. Keeping our own id is a
-- deliberate lock-in mitigation: history survives a change of auth provider.
-- -----------------------------------------------------------------------------
create table public.users (
  id            uuid primary key default gen_random_uuid(),
  auth_user_id  uuid unique,
  full_name     text not null,
  email         text not null unique,
  phone         text,
  designation   text,
  department    text,
  is_active     boolean not null default true,
  mfa_enabled   boolean not null default false,
  last_login_at timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid,
  updated_by    uuid,
  constraint users_email_lower_chk check (email = lower(email)),
  constraint users_full_name_not_blank check (btrim(full_name) <> '')
);

comment on table public.users is
  'Application users (staff). One row per person. id is our own identifier used by all audit columns; auth_user_id links to Supabase auth.users.';
comment on column public.users.auth_user_id is 'Supabase auth.users.id. Null until the user accepts an invite / signs up.';
comment on column public.users.is_active is 'Inactive users cannot sign in and RLS treats them as unauthenticated.';
comment on column public.users.created_by is 'User who created this row (FK users.id).';
comment on column public.users.updated_by is 'User who last updated this row (FK users.id).';

create index users_active_idx on public.users (is_active);
create index users_auth_user_idx on public.users (auth_user_id);

-- -----------------------------------------------------------------------------
-- roles
-- The role catalogue. code is the stable key used in user_roles and RLS.
-- -----------------------------------------------------------------------------
create table public.roles (
  code        text primary key,
  name        text not null,
  description text,
  is_system   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint roles_code_chk check (code ~ '^[a-z][a-z0-9_]*$')
);

comment on table public.roles is
  'Role catalogue. code is the stable key referenced by user_roles and used by all RLS policies.';
comment on column public.roles.is_system is 'True for the seeded roles that must not be deleted.';

-- -----------------------------------------------------------------------------
-- user_roles
-- Many-to-many between users and roles. Effective permissions are the union of
-- the active roles, except where segregation-of-duties triggers forbid.
-- -----------------------------------------------------------------------------
create table public.user_roles (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.users(id) on delete cascade,
  role_code  text not null references public.roles(code) on delete restrict,
  granted_at timestamptz not null default now(),
  granted_by uuid references public.users(id),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid,
  constraint user_roles_unique unique (user_id, role_code)
);

comment on table public.user_roles is
  'Grants a role to a user. A user may hold several roles; permissions are the union of active roles.';

create index user_roles_user_idx on public.user_roles (user_id);
create index user_roles_role_idx on public.user_roles (role_code);

-- ============================== 0003_security_helpers.sql ==============================
-- =============================================================================
-- 0003_security_helpers.sql
-- Security helper functions used by RLS policies and column defaults.
-- All are SECURITY DEFINER so they can read users/user_roles regardless of the
-- caller's own RLS, and STABLE so they are evaluated once per statement.
-- =============================================================================

-- The authenticated subject from the JWT (Supabase sets request.jwt.claims).
create or replace function app.jwt_sub()
returns uuid
language sql
stable
set search_path = pg_temp
as $$
  select (
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid;
$$;

comment on function app.jwt_sub() is
  'Returns the JWT subject (auth user id) as uuid, or NULL when unauthenticated.';

-- Our internal users.id for the signed-in subject. Matches on auth_user_id, or
-- on id as a fallback so the schema also works if ids are aligned.
create or replace function app.current_user_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select u.id
    from public.users u
   where u.is_active
     and (u.auth_user_id = app.jwt_sub() or u.id = app.jwt_sub())
   limit 1;
$$;

comment on function app.current_user_id() is
  'Returns the internal public.users.id of the signed-in user, or NULL if not authenticated/active.';

-- Active role codes held by the signed-in user.
create or replace function app.current_roles()
returns text[]
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(array_agg(ur.role_code order by ur.role_code), array[]::text[])
    from public.user_roles ur
   where ur.user_id = app.current_user_id()
     and (ur.expires_at is null or ur.expires_at > now());
$$;

comment on function app.current_roles() is
  'Returns the array of active role codes for the signed-in user.';

create or replace function app.has_role(p_role text)
returns boolean
language sql
stable
as $$
  select p_role = any (app.current_roles());
$$;

comment on function app.has_role(text) is 'True when the signed-in user holds the given role.';

create or replace function app.has_any_role(p_roles text[])
returns boolean
language sql
stable
as $$
  select app.current_roles() && p_roles;
$$;

comment on function app.has_any_role(text[]) is 'True when the signed-in user holds at least one of the given roles.';

create or replace function app.is_admin()
returns boolean
language sql
stable
as $$
  select app.has_role('admin');
$$;

comment on function app.is_admin() is 'True when the signed-in user holds the admin role.';

-- Any recognised, active role = a staff member allowed to read the business data.
create or replace function app.is_staff()
returns boolean
language sql
stable
as $$
  select app.has_any_role(array[
    'admin','management','sales','technical','procurement',
    'stores','qa','logistics','accounts','viewer'
  ]);
$$;

comment on function app.is_staff() is
  'True when the signed-in user holds any of the ten defined staff roles (i.e. is an authorised reader).';

create or replace function app.is_authenticated()
returns boolean
language sql
stable
as $$
  select app.current_user_id() is not null;
$$;

comment on function app.is_authenticated() is
  'True when the request maps to an active application user.';

-- Convenience grants: RLS policy expressions call these functions, so the
-- authenticated role needs EXECUTE on them.
grant usage on schema app to authenticated;
grant execute on all functions in schema app to authenticated;

-- ============================== 0004_masters.sql ==============================
-- =============================================================================
-- 0004_masters.sql
-- Master data: customers, contacts, products, specifications, OEMs.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- customers : defence buyers (MoD, DPSUs, armed forces, paramilitary, etc.)
-- -----------------------------------------------------------------------------
create table public.customers (
  id              uuid primary key default gen_random_uuid(),
  code            text not null unique,
  name            text not null,
  customer_type   text not null default 'other',
  address_line1   text,
  address_line2   text,
  city            text,
  state           text,
  pincode         text,
  country         text not null default 'India',
  gstin           text,
  pan             text,
  email           text,
  phone           text,
  website         text,
  status          text not null default 'active',
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  created_by      uuid,
  updated_by      uuid,
  constraint customers_type_chk check (customer_type in
    ('mod','dpsu','armed_forces','paramilitary','ordnance_factory','police','government_other','private','other')),
  constraint customers_status_chk check (status in ('active','inactive','blacklisted')),
  constraint customers_name_not_blank check (btrim(name) <> '')
);

comment on table public.customers is
  'Master list of defence customers / buyers. The organisation that places tenders and purchase orders.';
comment on column public.customers.code is 'Short unique business code for the customer.';
comment on column public.customers.customer_type is 'Buyer category (mod, dpsu, armed_forces, paramilitary, ...).';
comment on column public.customers.status is 'active | inactive | blacklisted.';

create index customers_status_idx on public.customers (status);
create index customers_name_idx on public.customers (name);

-- -----------------------------------------------------------------------------
-- customer_contacts
-- -----------------------------------------------------------------------------
create table public.customer_contacts (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  name        text not null,
  designation text,
  email       text,
  phone       text,
  is_primary  boolean not null default false,
  notes       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid,
  updated_by  uuid,
  constraint customer_contacts_name_not_blank check (btrim(name) <> '')
);

comment on table public.customer_contacts is
  'People at a customer organisation. One customer may have many contacts; at most one primary.';

create index customer_contacts_customer_idx on public.customer_contacts (customer_id);
create unique index customer_contacts_one_primary_idx
  on public.customer_contacts (customer_id) where (is_primary);

-- -----------------------------------------------------------------------------
-- products : item master (the natural key across the whole supply chain)
-- -----------------------------------------------------------------------------
create table public.products (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique,
  name          text not null,
  description   text,
  category      text,
  unit          text not null default 'NO',
  hsn_code      text,
  manufacturer  text,
  part_number   text,
  is_serialized boolean not null default false,
  status        text not null default 'active',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid,
  updated_by    uuid,
  constraint products_status_chk check (status in ('active','inactive','obsolete')),
  constraint products_name_not_blank check (btrim(name) <> ''),
  constraint products_unit_not_blank check (btrim(unit) <> '')
);

comment on table public.products is
  'Item master. Every tender line, quotation line, order line, PO line and dispatch line refers back to one product.';
comment on column public.products.unit is 'Unit of measure (e.g. NO, SET, KG, MTR).';
comment on column public.products.status is 'active | inactive | obsolete.';

create index products_status_idx on public.products (status);
create index products_category_idx on public.products (category);

-- -----------------------------------------------------------------------------
-- product_specifications : key/value technical specifications per product
-- -----------------------------------------------------------------------------
create table public.product_specifications (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references public.products(id) on delete cascade,
  spec_key    text not null,
  spec_value  text not null,
  unit        text,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid,
  updated_by  uuid,
  constraint product_specifications_unique unique (product_id, spec_key)
);

comment on table public.product_specifications is
  'Technical specification lines for a product (normalised instead of a free-text blob, so specs are comparable).';

create index product_specifications_product_idx on public.product_specifications (product_id);

-- -----------------------------------------------------------------------------
-- oems : OEM supplier master
-- -----------------------------------------------------------------------------
create table public.oems (
  id             uuid primary key default gen_random_uuid(),
  code           text not null unique,
  name           text not null,
  oem_type       text,
  address_line1  text,
  address_line2  text,
  city           text,
  state          text,
  pincode        text,
  country        text not null default 'India',
  gstin          text,
  pan            text,
  email          text,
  phone          text,
  website        text,
  payment_terms  text,
  status         text not null default 'active',
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     uuid,
  updated_by     uuid,
  constraint oems_status_chk check (status in ('active','inactive','blacklisted')),
  constraint oems_name_not_blank check (btrim(name) <> '')
);

comment on table public.oems is
  'OEM / supplier master. Original equipment manufacturers from whom pricing is collected and materials are purchased.';
comment on column public.oems.status is 'active | inactive | blacklisted.';

create index oems_status_idx on public.oems (status);
create index oems_name_idx on public.oems (name);

-- -----------------------------------------------------------------------------
-- oem_contacts
-- -----------------------------------------------------------------------------
create table public.oem_contacts (
  id         uuid primary key default gen_random_uuid(),
  oem_id     uuid not null references public.oems(id) on delete cascade,
  name       text not null,
  designation text,
  email      text,
  phone      text,
  is_primary boolean not null default false,
  notes      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid,
  constraint oem_contacts_name_not_blank check (btrim(name) <> '')
);

comment on table public.oem_contacts is
  'People at an OEM. One OEM may have many contacts; at most one primary.';

create index oem_contacts_oem_idx on public.oem_contacts (oem_id);
create unique index oem_contacts_one_primary_idx
  on public.oem_contacts (oem_id) where (is_primary);

-- -----------------------------------------------------------------------------
-- oem_products : which OEM supplies which product, under which part number
-- -----------------------------------------------------------------------------
create table public.oem_products (
  id              uuid primary key default gen_random_uuid(),
  oem_id          uuid not null references public.oems(id) on delete cascade,
  product_id      uuid not null references public.products(id) on delete cascade,
  oem_part_number text,
  lead_time_days  integer,
  moq             numeric(14,3),
  currency        text not null default 'INR',
  status          text not null default 'active',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  created_by      uuid,
  updated_by      uuid,
  constraint oem_products_unique unique (oem_id, product_id),
  constraint oem_products_status_chk check (status in ('active','inactive')),
  constraint oem_products_lead_time_chk check (lead_time_days is null or lead_time_days >= 0),
  constraint oem_products_moq_chk check (moq is null or moq > 0)
);

comment on table public.oem_products is
  'Approved product-to-OEM mapping with the OEM part number, lead time and MOQ. Prevents duplicate supplier rows per product.';

create index oem_products_oem_idx on public.oem_products (oem_id);
create index oem_products_product_idx on public.oem_products (product_id);

-- -----------------------------------------------------------------------------
-- oem_price_history : historical price points per OEM and product
-- -----------------------------------------------------------------------------
create table public.oem_price_history (
  id             uuid primary key default gen_random_uuid(),
  oem_id         uuid not null references public.oems(id) on delete cascade,
  product_id     uuid not null references public.products(id) on delete cascade,
  oem_product_id uuid references public.oem_products(id) on delete set null,
  unit_price     numeric(14,2) not null,
  currency       text not null default 'INR',
  valid_from     date not null default current_date,
  valid_to       date,
  source         text not null default 'quote',
  reference      text,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     uuid,
  updated_by     uuid,
  constraint oem_price_history_price_chk check (unit_price >= 0),
  constraint oem_price_history_source_chk check (source in ('quote','purchase_order','invoice','verbal','other')),
  constraint oem_price_history_dates_chk check (valid_to is null or valid_to >= valid_from)
);

comment on table public.oem_price_history is
  'Append-style history of prices quoted/paid per OEM and product, so the last cost is never lost in an inbox.';
comment on column public.oem_price_history.source is 'quote | purchase_order | invoice | verbal | other.';

create index oem_price_history_lookup_idx
  on public.oem_price_history (oem_id, product_id, valid_from desc);
create index oem_price_history_product_idx on public.oem_price_history (product_id);

-- ============================== 0005_documents.sql ==============================
-- =============================================================================
-- 0005_documents.sql
-- Central document/file register. Files themselves live in Supabase Storage;
-- this table holds the metadata and the classification that drives access.
-- Created before the tables that link to it (tender_documents, delivery_documents).
-- =============================================================================

create table public.documents (
  id              uuid primary key default gen_random_uuid(),
  title           text,
  file_name       text not null,
  storage_bucket  text not null default 'documents',
  storage_path    text not null,
  mime_type       text,
  size_bytes      bigint,
  classification  text not null default 'internal',
  entity_table    text,
  entity_id       uuid,
  version         integer not null default 1,
  checksum        text,
  uploaded_by     uuid references public.users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  created_by      uuid,
  updated_by      uuid,
  constraint documents_classification_chk check
    (classification in ('unclassified','internal','confidential','controlled','itar_ear')),
  constraint documents_path_unique unique (storage_bucket, storage_path),
  constraint documents_version_chk check (version >= 1),
  constraint documents_size_chk check (size_bytes is null or size_bytes >= 0)
);

comment on table public.documents is
  'Central register of uploaded files (tender docs, quotations, POs, inspection certificates, invoices, PODs). The file bytes live in Supabase Storage; access is via short-lived signed URLs.';
comment on column public.documents.classification is
  'unclassified | internal | confidential | controlled | itar_ear. controlled/itar_ear rows are limited to admin, management, technical and qa.';
comment on column public.documents.entity_table is
  'Optional generic link to any business table (used together with entity_id). Explicit link tables also exist (tender_documents, delivery_documents).';

create index documents_entity_idx on public.documents (entity_table, entity_id);
create index documents_classification_idx on public.documents (classification);
create index documents_uploaded_by_idx on public.documents (uploaded_by);

-- ============================== 0006_tenders.sql ==============================
-- =============================================================================
-- 0006_tenders.sql
-- Tender / enquiry domain: tenders, their documents, technical requirements,
-- pre-tender opportunities, opportunity requirements and compliance items.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- tenders : a received defence tender / enquiry
-- -----------------------------------------------------------------------------
create table public.tenders (
  id                uuid primary key default gen_random_uuid(),
  tender_no         text not null unique,
  customer_id       uuid not null references public.customers(id) on delete restrict,
  title             text not null,
  description       text,
  source            text,
  category          text,
  received_date     date not null default current_date,
  bid_due_date      date,
  corrigendum_date  date,
  emd_amount        numeric(14,2),
  emd_exempt        boolean not null default false,
  bid_validity_date date,
  currency          text not null default 'INR',
  estimated_value   numeric(14,2),
  priority          text not null default 'medium',
  status            text not null default 'received',
  owner_user_id     uuid references public.users(id),
  notes             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid,
  updated_by        uuid,
  constraint tenders_status_chk check (status in
    ('draft','received','under_analysis','rfq_sent','quoted','submitted','under_evaluation',
     'won','lost','cancelled','closed')),
  constraint tenders_priority_chk check (priority in ('low','medium','high','critical')),
  constraint tenders_title_not_blank check (btrim(title) <> ''),
  constraint tenders_due_after_received_chk check (bid_due_date is null or bid_due_date >= received_date),
  constraint tenders_emd_chk check (emd_amount is null or emd_amount >= 0)
);

comment on table public.tenders is
  'A defence tender or enquiry received from a customer. Root of the sales chain.';
comment on column public.tenders.tender_no is 'Customer tender/reference number. Unique.';
comment on column public.tenders.status is
  'draft | received | under_analysis | rfq_sent | quoted | submitted | under_evaluation | won | lost | cancelled | closed.';
comment on column public.tenders.bid_due_date is 'Submission deadline; drives reminder alerts.';
comment on column public.tenders.emd_amount is 'Earnest Money Deposit required, in the tender currency.';

create index tenders_customer_idx on public.tenders (customer_id);
create index tenders_status_idx on public.tenders (status);
create index tenders_bid_due_idx on public.tenders (bid_due_date);
create index tenders_owner_idx on public.tenders (owner_user_id);

-- -----------------------------------------------------------------------------
-- tender_documents : links documents to a tender
-- -----------------------------------------------------------------------------
create table public.tender_documents (
  id          uuid primary key default gen_random_uuid(),
  tender_id   uuid not null references public.tenders(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,
  doc_type    text not null default 'other',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid,
  updated_by  uuid,
  constraint tender_documents_unique unique (tender_id, document_id),
  constraint tender_documents_doc_type_chk check (doc_type in
    ('tender_document','corrigendum','technical_spec','drawing','emd_proof','other'))
);

comment on table public.tender_documents is
  'Associates a stored document with a tender (tender document, corrigendum, spec, drawing, EMD proof).';

create index tender_documents_tender_idx on public.tender_documents (tender_id);
create index tender_documents_document_idx on public.tender_documents (document_id);

-- -----------------------------------------------------------------------------
-- tender_requirements : technical requirement line items of a tender
-- -----------------------------------------------------------------------------
create table public.tender_requirements (
  id                uuid primary key default gen_random_uuid(),
  tender_id         uuid not null references public.tenders(id) on delete cascade,
  line_no           integer not null,
  product_id        uuid references public.products(id) on delete set null,
  description       text not null,
  specification     text,
  quantity          numeric(14,3) not null,
  unit              text not null default 'NO',
  feasibility       text not null default 'feasible',
  compliance_status text not null default 'pending',
  technical_notes   text,
  assigned_to       uuid references public.users(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid,
  updated_by        uuid,
  constraint tender_requirements_unique unique (tender_id, line_no),
  constraint tender_requirements_qty_chk check (quantity > 0),
  constraint tender_requirements_feasibility_chk check (feasibility in
    ('feasible','clarification_needed','not_feasible')),
  constraint tender_requirements_compliance_chk check (compliance_status in
    ('pending','compliant','partially_compliant','non_compliant','not_applicable')),
  constraint tender_requirements_desc_not_blank check (btrim(description) <> '')
);

comment on table public.tender_requirements is
  'Technical requirement lines of a tender: what the customer asked for, quantity, spec and feasibility.';
comment on column public.tender_requirements.feasibility is
  'Engineering assessment: feasible | clarification_needed | not_feasible.';
comment on column public.tender_requirements.compliance_status is
  'How we comply: pending | compliant | partially_compliant | non_compliant | not_applicable.';

create index tender_requirements_tender_idx on public.tender_requirements (tender_id);
create index tender_requirements_product_idx on public.tender_requirements (product_id);

-- -----------------------------------------------------------------------------
-- opportunities : pre-tender / sales opportunities (not yet a formal tender)
-- -----------------------------------------------------------------------------
create table public.opportunities (
  id                  uuid primary key default gen_random_uuid(),
  customer_id         uuid not null references public.customers(id) on delete restrict,
  title               text not null,
  description         text,
  source              text,
  estimated_value     numeric(14,2),
  currency            text not null default 'INR',
  probability         integer,
  expected_close_date date,
  stage               text not null default 'new',
  owner_user_id       uuid references public.users(id),
  notes               text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid,
  updated_by          uuid,
  constraint opportunities_stage_chk check (stage in
    ('new','qualified','proposal','negotiation','won','lost','on_hold')),
  constraint opportunities_probability_chk check (probability is null or (probability between 0 and 100)),
  constraint opportunities_value_chk check (estimated_value is null or estimated_value >= 0),
  constraint opportunities_title_not_blank check (btrim(title) <> '')
);

comment on table public.opportunities is
  'A sales opportunity that may or may not become a formal tender. Distinct from tenders so pre-bid work is tracked.';
comment on column public.opportunities.stage is
  'new | qualified | proposal | negotiation | won | lost | on_hold.';

create index opportunities_customer_idx on public.opportunities (customer_id);
create index opportunities_stage_idx on public.opportunities (stage);
create index opportunities_owner_idx on public.opportunities (owner_user_id);

-- -----------------------------------------------------------------------------
-- requirements : requirements belonging to an opportunity and/or a tender
-- -----------------------------------------------------------------------------
create table public.requirements (
  id               uuid primary key default gen_random_uuid(),
  opportunity_id   uuid references public.opportunities(id) on delete cascade,
  tender_id        uuid references public.tenders(id) on delete cascade,
  description      text not null,
  requirement_type text,
  priority         text not null default 'medium',
  status           text not null default 'open',
  owner_user_id    uuid references public.users(id),
  due_date         date,
  notes            text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  created_by       uuid,
  updated_by       uuid,
  constraint requirements_parent_chk check (opportunity_id is not null or tender_id is not null),
  constraint requirements_priority_chk check (priority in ('low','medium','high','critical')),
  constraint requirements_status_chk check (status in ('open','in_progress','met','not_met','deferred')),
  constraint requirements_desc_not_blank check (btrim(description) <> '')
);

comment on table public.requirements is
  'General requirement items attached to an opportunity and/or a tender (broader than technical lines). At least one parent is required.';

create index requirements_opportunity_idx on public.requirements (opportunity_id);
create index requirements_tender_idx on public.requirements (tender_id);
create index requirements_status_idx on public.requirements (status);

-- -----------------------------------------------------------------------------
-- compliance_items : compliance checklist per tender / opportunity
-- -----------------------------------------------------------------------------
create table public.compliance_items (
  id                uuid primary key default gen_random_uuid(),
  tender_id         uuid references public.tenders(id) on delete cascade,
  opportunity_id    uuid references public.opportunities(id) on delete cascade,
  requirement       text not null,
  reference_clause  text,
  is_mandatory      boolean not null default true,
  compliance_status text not null default 'pending',
  evidence          text,
  verified_by       uuid references public.users(id),
  verified_at       timestamptz,
  notes             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid,
  updated_by        uuid,
  constraint compliance_items_parent_chk check (tender_id is not null or opportunity_id is not null),
  constraint compliance_items_status_chk check (compliance_status in
    ('pending','compliant','partially_compliant','non_compliant','not_applicable')),
  constraint compliance_items_requirement_not_blank check (btrim(requirement) <> '')
);

comment on table public.compliance_items is
  'Compliance / eligibility checklist for a tender or opportunity (mandatory clauses, certifications, evidence, verification).';

create index compliance_items_tender_idx on public.compliance_items (tender_id);
create index compliance_items_opportunity_idx on public.compliance_items (opportunity_id);
create index compliance_items_status_idx on public.compliance_items (compliance_status);

-- ============================== 0007_quotations.sql ==============================
-- =============================================================================
-- 0007_quotations.sql
-- Quotations to the customer: versioned header, line items, approval trail.
-- Header totals are recalculated from line items by trigger (0013).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- quotations : a versioned quotation submitted to a customer
-- -----------------------------------------------------------------------------
create table public.quotations (
  id                uuid primary key default gen_random_uuid(),
  quotation_no      text not null,
  version           integer not null default 1,
  customer_id       uuid not null references public.customers(id) on delete restrict,
  tender_id         uuid references public.tenders(id) on delete set null,
  opportunity_id    uuid references public.opportunities(id) on delete set null,
  quote_date        date not null default current_date,
  validity_date     date,
  currency          text not null default 'INR',
  subtotal          numeric(14,2) not null default 0,
  tax_total         numeric(14,2) not null default 0,
  grand_total       numeric(14,2) not null default 0,
  margin_pct        numeric(6,2),
  status            text not null default 'draft',
  submitted_at      timestamptz,
  notes             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid,
  updated_by        uuid,
  constraint quotations_no_version_unique unique (quotation_no, version),
  constraint quotations_version_chk check (version >= 1),
  constraint quotations_status_chk check (status in
    ('draft','pending_approval','approved','rejected','submitted','revised','won','lost','expired')),
  constraint quotations_validity_chk check (validity_date is null or validity_date >= quote_date),
  constraint quotations_money_chk check (subtotal >= 0 and tax_total >= 0 and grand_total >= 0)
);

comment on table public.quotations is
  'A quotation to a customer. Versioned: a new revision is a new row, a submitted version is never overwritten.';
comment on column public.quotations.status is
  'draft | pending_approval | approved | rejected | submitted | revised | won | lost | expired.';
comment on column public.quotations.subtotal is 'Recalculated by trigger from quotation_items (net of tax).';
comment on column public.quotations.tax_total is 'Recalculated by trigger from quotation_items.';
comment on column public.quotations.grand_total is 'Recalculated by trigger from quotation_items (tax inclusive).';

create index quotations_customer_idx on public.quotations (customer_id);
create index quotations_tender_idx on public.quotations (tender_id);
create index quotations_status_idx on public.quotations (status);

-- -----------------------------------------------------------------------------
-- quotation_items
-- line_total is a GENERATED column, so a line's total can never disagree with
-- its own quantity/price/discount/tax (requirement: avoid duplicate data).
-- -----------------------------------------------------------------------------
create table public.quotation_items (
  id                    uuid primary key default gen_random_uuid(),
  quotation_id          uuid not null references public.quotations(id) on delete cascade,
  line_no               integer not null,
  product_id            uuid references public.products(id) on delete set null,
  tender_requirement_id uuid references public.tender_requirements(id) on delete set null,
  source_oem_id         uuid references public.oems(id) on delete set null,
  description           text not null,
  quantity              numeric(14,3) not null,
  unit                  text not null default 'NO',
  unit_price            numeric(14,2) not null default 0,
  discount_pct          numeric(6,2) not null default 0,
  tax_pct               numeric(6,2) not null default 0,
  line_total            numeric(14,2) generated always as
    (round(quantity * unit_price * (1 - discount_pct / 100) * (1 + tax_pct / 100), 2)) stored,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  created_by            uuid,
  updated_by            uuid,
  constraint quotation_items_unique unique (quotation_id, line_no),
  constraint quotation_items_qty_chk check (quantity > 0),
  constraint quotation_items_price_chk check (unit_price >= 0),
  constraint quotation_items_discount_chk check (discount_pct between 0 and 100),
  constraint quotation_items_tax_chk check (tax_pct between 0 and 100),
  constraint quotation_items_desc_not_blank check (btrim(description) <> '')
);

comment on table public.quotation_items is
  'Line items of a quotation. line_total is generated from quantity, unit_price, discount_pct and tax_pct.';
comment on column public.quotation_items.line_total is
  'GENERATED: round(quantity * unit_price * (1 - discount/100) * (1 + tax/100), 2).';

create index quotation_items_quotation_idx on public.quotation_items (quotation_id);
create index quotation_items_product_idx on public.quotation_items (product_id);

-- -----------------------------------------------------------------------------
-- quotation_approvals : approval trail (may have several steps)
-- -----------------------------------------------------------------------------
create table public.quotation_approvals (
  id               uuid primary key default gen_random_uuid(),
  quotation_id     uuid not null references public.quotations(id) on delete cascade,
  step_no          integer not null default 1,
  approver_user_id uuid references public.users(id),
  decision         text not null default 'pending',
  comments         text,
  decided_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  created_by       uuid,
  updated_by       uuid,
  constraint quotation_approvals_unique unique (quotation_id, step_no),
  constraint quotation_approvals_decision_chk check (decision in ('pending','approved','rejected','returned')),
  constraint quotation_approvals_step_chk check (step_no >= 1)
);

comment on table public.quotation_approvals is
  'Approval steps for a quotation. A quotation above the configured value cannot be submitted until an approved step exists.';

create index quotation_approvals_quotation_idx on public.quotation_approvals (quotation_id);
create index quotation_approvals_approver_idx on public.quotation_approvals (approver_user_id);

-- ============================== 0008_orders_procurement.sql ==============================
-- =============================================================================
-- 0008_orders_procurement.sql
-- Customer purchase orders and the procurement path: purchase requests,
-- purchase orders to OEMs, and their line items.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- customer_orders : a purchase order received from the customer
-- -----------------------------------------------------------------------------
create table public.customer_orders (
  id               uuid primary key default gen_random_uuid(),
  order_no         text not null,
  order_date       date not null default current_date,
  customer_id      uuid not null references public.customers(id) on delete restrict,
  quotation_id     uuid references public.quotations(id) on delete set null,
  currency         text not null default 'INR',
  subtotal         numeric(14,2) not null default 0,
  tax_total        numeric(14,2) not null default 0,
  grand_total      numeric(14,2) not null default 0,
  delivery_terms   text,
  payment_terms    text,
  consignee_name   text,
  consignee_address text,
  status           text not null default 'received',
  notes            text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  created_by       uuid,
  updated_by       uuid,
  constraint customer_orders_no_unique unique (customer_id, order_no),
  constraint customer_orders_status_chk check (status in
    ('received','confirmed','in_procurement','partially_delivered','delivered','invoiced','closed','cancelled')),
  constraint customer_orders_money_chk check (subtotal >= 0 and tax_total >= 0 and grand_total >= 0)
);

comment on table public.customer_orders is
  'A purchase order received from a defence customer, normally resulting from a won quotation.';
comment on column public.customer_orders.order_no is 'Customer PO number. Unique per customer.';
comment on column public.customer_orders.status is
  'received | confirmed | in_procurement | partially_delivered | delivered | invoiced | closed | cancelled.';

create index customer_orders_customer_idx on public.customer_orders (customer_id);
create index customer_orders_status_idx on public.customer_orders (status);
create index customer_orders_quotation_idx on public.customer_orders (quotation_id);

-- -----------------------------------------------------------------------------
-- order_items : line items of a customer order
-- -----------------------------------------------------------------------------
create table public.order_items (
  id                uuid primary key default gen_random_uuid(),
  customer_order_id uuid not null references public.customer_orders(id) on delete cascade,
  line_no           integer not null,
  product_id        uuid references public.products(id) on delete set null,
  quotation_item_id uuid references public.quotation_items(id) on delete set null,
  description       text not null,
  quantity          numeric(14,3) not null,
  unit              text not null default 'NO',
  unit_price        numeric(14,2) not null default 0,
  discount_pct      numeric(6,2) not null default 0,
  tax_pct           numeric(6,2) not null default 0,
  line_total        numeric(14,2) generated always as
    (round(quantity * unit_price * (1 - discount_pct / 100) * (1 + tax_pct / 100), 2)) stored,
  delivered_qty     numeric(14,3) not null default 0,
  status            text not null default 'open',
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid,
  updated_by        uuid,
  constraint order_items_unique unique (customer_order_id, line_no),
  constraint order_items_qty_chk check (quantity > 0),
  constraint order_items_price_chk check (unit_price >= 0),
  constraint order_items_delivered_chk check (delivered_qty >= 0),
  constraint order_items_status_chk check (status in ('open','partially_delivered','delivered','cancelled')),
  constraint order_items_desc_not_blank check (btrim(description) <> '')
);

comment on table public.order_items is
  'Line items of a customer order. matched to a quotation line where possible. delivered_qty tracks fulfilment.';

create index order_items_order_idx on public.order_items (customer_order_id);
create index order_items_product_idx on public.order_items (product_id);

-- -----------------------------------------------------------------------------
-- purchase_requests : internal request to procure (before a PO to an OEM)
-- -----------------------------------------------------------------------------
create table public.purchase_requests (
  id                 uuid primary key default gen_random_uuid(),
  request_no         text not null unique,
  customer_order_id  uuid references public.customer_orders(id) on delete set null,
  requested_by       uuid references public.users(id),
  needed_by          date,
  priority           text not null default 'medium',
  status             text not null default 'draft',
  notes              text,
  approved_by        uuid references public.users(id),
  approved_at        timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  created_by         uuid,
  updated_by         uuid,
  constraint purchase_requests_status_chk check (status in
    ('draft','submitted','approved','rejected','converted','cancelled')),
  constraint purchase_requests_priority_chk check (priority in ('low','medium','high','critical'))
);

comment on table public.purchase_requests is
  'Internal purchase request raised (for an order or as stock), approved, then converted into purchase orders to OEMs.';
comment on column public.purchase_requests.status is
  'draft | submitted | approved | rejected | converted | cancelled.';

create index purchase_requests_order_idx on public.purchase_requests (customer_order_id);
create index purchase_requests_status_idx on public.purchase_requests (status);

-- -----------------------------------------------------------------------------
-- purchase_request_items
-- -----------------------------------------------------------------------------
create table public.purchase_request_items (
  id                  uuid primary key default gen_random_uuid(),
  purchase_request_id uuid not null references public.purchase_requests(id) on delete cascade,
  line_no             integer not null,
  product_id          uuid references public.products(id) on delete set null,
  description         text not null,
  quantity            numeric(14,3) not null,
  unit                text not null default 'NO',
  required_by         date,
  status              text not null default 'open',
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid,
  updated_by          uuid,
  constraint purchase_request_items_unique unique (purchase_request_id, line_no),
  constraint purchase_request_items_qty_chk check (quantity > 0),
  constraint purchase_request_items_status_chk check (status in ('open','converted','cancelled'))
);

comment on table public.purchase_request_items is 'Line items of a purchase request.';

create index purchase_request_items_request_idx on public.purchase_request_items (purchase_request_id);

-- -----------------------------------------------------------------------------
-- purchase_orders : a PO issued to an OEM
-- -----------------------------------------------------------------------------
create table public.purchase_orders (
  id                    uuid primary key default gen_random_uuid(),
  po_no                 text not null unique,
  po_date               date not null default current_date,
  oem_id                uuid not null references public.oems(id) on delete restrict,
  customer_order_id     uuid references public.customer_orders(id) on delete set null,
  purchase_request_id   uuid references public.purchase_requests(id) on delete set null,
  currency              text not null default 'INR',
  subtotal              numeric(14,2) not null default 0,
  tax_total             numeric(14,2) not null default 0,
  grand_total           numeric(14,2) not null default 0,
  expected_delivery_date date,
  terms                 text,
  status                text not null default 'draft',
  approved_by           uuid references public.users(id),
  approved_at           timestamptz,
  notes                 text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  created_by            uuid,
  updated_by            uuid,
  constraint purchase_orders_status_chk check (status in
    ('draft','pending_approval','approved','sent','partially_received','received','cancelled','closed')),
  constraint purchase_orders_money_chk check (subtotal >= 0 and tax_total >= 0 and grand_total >= 0)
);

comment on table public.purchase_orders is
  'A purchase order issued to an OEM supplier. Header totals are recalculated from purchase_order_items by trigger.';
comment on column public.purchase_orders.status is
  'draft | pending_approval | approved | sent | partially_received | received | cancelled | closed.';

create index purchase_orders_oem_idx on public.purchase_orders (oem_id);
create index purchase_orders_order_idx on public.purchase_orders (customer_order_id);
create index purchase_orders_status_idx on public.purchase_orders (status);
create index purchase_orders_expected_idx on public.purchase_orders (expected_delivery_date);

-- -----------------------------------------------------------------------------
-- purchase_order_items
-- -----------------------------------------------------------------------------
create table public.purchase_order_items (
  id                  uuid primary key default gen_random_uuid(),
  purchase_order_id   uuid not null references public.purchase_orders(id) on delete cascade,
  line_no             integer not null,
  product_id          uuid references public.products(id) on delete set null,
  order_item_id       uuid references public.order_items(id) on delete set null,
  description         text not null,
  quantity            numeric(14,3) not null,
  unit                text not null default 'NO',
  unit_price          numeric(14,2) not null default 0,
  discount_pct        numeric(6,2) not null default 0,
  tax_pct             numeric(6,2) not null default 0,
  line_total          numeric(14,2) generated always as
    (round(quantity * unit_price * (1 - discount_pct / 100) * (1 + tax_pct / 100), 2)) stored,
  received_qty        numeric(14,3) not null default 0,
  status              text not null default 'open',
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid,
  updated_by          uuid,
  constraint purchase_order_items_unique unique (purchase_order_id, line_no),
  constraint purchase_order_items_qty_chk check (quantity > 0),
  constraint purchase_order_items_price_chk check (unit_price >= 0),
  constraint purchase_order_items_received_chk check (received_qty >= 0),
  constraint purchase_order_items_status_chk check (status in ('open','partially_received','received','cancelled')),
  constraint purchase_order_items_desc_not_blank check (btrim(description) <> '')
);

comment on table public.purchase_order_items is
  'Line items of a purchase order to an OEM. received_qty tracks goods receipt.';

create index purchase_order_items_po_idx on public.purchase_order_items (purchase_order_id);
create index purchase_order_items_product_idx on public.purchase_order_items (product_id);

-- ============================== 0009_receipts_inspection.sql ==============================
-- =============================================================================
-- 0009_receipts_inspection.sql
-- Goods receipt from OEMs (material receipts) and inspection / PDI records.
-- A failed PDI must block dispatch; that gate is enforced by trigger in 0013.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- material_receipts : goods receipt note against a purchase order
-- -----------------------------------------------------------------------------
create table public.material_receipts (
  id                uuid primary key default gen_random_uuid(),
  grn_no            text not null unique,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete restrict,
  oem_id            uuid not null references public.oems(id) on delete restrict,
  docket_no         text,
  dispatch_date     date,
  expected_date     date,
  received_date     date,
  received_by       uuid references public.users(id),
  status            text not null default 'pending',
  inspection_status text not null default 'pending',
  notes             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid,
  updated_by        uuid,
  constraint material_receipts_status_chk check (status in ('pending','partial','received','rejected')),
  constraint material_receipts_inspection_chk check (inspection_status in
    ('pending','in_progress','passed','failed','partial'))
);

comment on table public.material_receipts is
  'Goods receipt note (GRN) recording material received from an OEM against a purchase order, whole or partial.';
comment on column public.material_receipts.status is 'pending | partial | received | rejected.';
comment on column public.material_receipts.inspection_status is
  'Rolling inspection state of this receipt: pending | in_progress | passed | failed | partial.';

create index material_receipts_po_idx on public.material_receipts (purchase_order_id);
create index material_receipts_oem_idx on public.material_receipts (oem_id);
create index material_receipts_status_idx on public.material_receipts (status);

-- -----------------------------------------------------------------------------
-- material_receipt_items
-- -----------------------------------------------------------------------------
create table public.material_receipt_items (
  id                       uuid primary key default gen_random_uuid(),
  material_receipt_id      uuid not null references public.material_receipts(id) on delete cascade,
  purchase_order_item_id   uuid not null references public.purchase_order_items(id) on delete restrict,
  product_id               uuid references public.products(id) on delete set null,
  qty_received             numeric(14,3) not null default 0,
  qty_accepted             numeric(14,3) not null default 0,
  qty_rejected             numeric(14,3) not null default 0,
  remarks                  text,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  created_by               uuid,
  updated_by               uuid,
  constraint material_receipt_items_qty_chk check (qty_received >= 0 and qty_accepted >= 0 and qty_rejected >= 0),
  constraint material_receipt_items_split_chk check (qty_accepted + qty_rejected <= qty_received)
);

comment on table public.material_receipt_items is
  'Received quantities per purchase-order line, split into accepted and rejected after inspection.';

create index material_receipt_items_receipt_idx on public.material_receipt_items (material_receipt_id);
create index material_receipt_items_po_item_idx on public.material_receipt_items (purchase_order_item_id);

-- -----------------------------------------------------------------------------
-- pdi_records : inspection / pre-delivery inspection record
-- -----------------------------------------------------------------------------
create table public.pdi_records (
  id                  uuid primary key default gen_random_uuid(),
  pdi_no              text not null unique,
  material_receipt_id uuid references public.material_receipts(id) on delete set null,
  customer_order_id   uuid references public.customer_orders(id) on delete set null,
  inspection_type     text not null default 'pdi',
  inspection_date     date not null default current_date,
  inspector_user_id   uuid references public.users(id),
  agency              text,
  result              text not null default 'pending',
  certificate_no      text,
  certificate_date    date,
  notes               text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid,
  updated_by          uuid,
  constraint pdi_records_type_chk check (inspection_type in
    ('incoming','in_process','final','pdi','third_party','dgqa','dgaqa')),
  constraint pdi_records_result_chk check (result in ('pending','pass','fail','conditional'))
);

comment on table public.pdi_records is
  'Inspection / PDI record. result = pass is required before the related order lines may be dispatched.';
comment on column public.pdi_records.inspection_type is
  'incoming | in_process | final | pdi | third_party | dgqa | dgaqa.';
comment on column public.pdi_records.result is 'pending | pass | fail | conditional.';

create index pdi_records_receipt_idx on public.pdi_records (material_receipt_id);
create index pdi_records_order_idx on public.pdi_records (customer_order_id);
create index pdi_records_result_idx on public.pdi_records (result);

-- -----------------------------------------------------------------------------
-- pdi_items
-- -----------------------------------------------------------------------------
create table public.pdi_items (
  id                      uuid primary key default gen_random_uuid(),
  pdi_record_id           uuid not null references public.pdi_records(id) on delete cascade,
  material_receipt_item_id uuid references public.material_receipt_items(id) on delete set null,
  product_id              uuid references public.products(id) on delete set null,
  qty_inspected           numeric(14,3) not null default 0,
  qty_passed              numeric(14,3) not null default 0,
  qty_failed              numeric(14,3) not null default 0,
  defect_code             text,
  defect_notes            text,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  created_by              uuid,
  updated_by              uuid,
  constraint pdi_items_qty_chk check (qty_inspected >= 0 and qty_passed >= 0 and qty_failed >= 0),
  constraint pdi_items_split_chk check (qty_passed + qty_failed <= qty_inspected)
);

comment on table public.pdi_items is
  'Inspection result per received line: quantity inspected, passed, failed and defect notes.';

create index pdi_items_pdi_idx on public.pdi_items (pdi_record_id);
create index pdi_items_receipt_item_idx on public.pdi_items (material_receipt_item_id);

-- ============================== 0010_dispatch_finance.sql ==============================
-- =============================================================================
-- 0010_dispatch_finance.sql
-- Dispatch to the defence customer, delivery documents, invoicing, payments
-- and warranties.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- dispatches : a shipment to the customer
-- -----------------------------------------------------------------------------
create table public.dispatches (
  id                    uuid primary key default gen_random_uuid(),
  dispatch_no           text not null unique,
  customer_order_id     uuid not null references public.customer_orders(id) on delete restrict,
  customer_id           uuid not null references public.customers(id) on delete restrict,
  dispatch_date         date not null default current_date,
  carrier               text,
  tracking_no           text,
  eway_bill_no          text,
  consignee_name        text,
  consignee_address     text,
  status                text not null default 'prepared',
  delivery_confirmed_date date,
  pod_document_id       uuid references public.documents(id) on delete set null,
  notes                 text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  created_by            uuid,
  updated_by            uuid,
  constraint dispatches_status_chk check (status in
    ('prepared','dispatched','in_transit','delivered','returned','cancelled')),
  constraint dispatches_delivery_chk check
    (delivery_confirmed_date is null or delivery_confirmed_date >= dispatch_date)
);

comment on table public.dispatches is
  'A dispatch/shipment to the defence customer. May be partial. pod_document_id holds the proof of delivery.';
comment on column public.dispatches.status is
  'prepared | dispatched | in_transit | delivered | returned | cancelled.';

create index dispatches_order_idx on public.dispatches (customer_order_id);
create index dispatches_customer_idx on public.dispatches (customer_id);
create index dispatches_status_idx on public.dispatches (status);

-- -----------------------------------------------------------------------------
-- dispatch_items
-- -----------------------------------------------------------------------------
create table public.dispatch_items (
  id              uuid primary key default gen_random_uuid(),
  dispatch_id     uuid not null references public.dispatches(id) on delete cascade,
  order_item_id   uuid not null references public.order_items(id) on delete restrict,
  product_id      uuid references public.products(id) on delete set null,
  quantity        numeric(14,3) not null,
  packing_details text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  created_by      uuid,
  updated_by      uuid,
  constraint dispatch_items_qty_chk check (quantity > 0)
);

comment on table public.dispatch_items is
  'Line items of a dispatch. A dispatch line is only allowed when the related order line has passed inspection (see 0013).';

create index dispatch_items_dispatch_idx on public.dispatch_items (dispatch_id);
create index dispatch_items_order_item_idx on public.dispatch_items (order_item_id);

-- -----------------------------------------------------------------------------
-- delivery_documents : documents attached to a dispatch (POD, e-way bill, etc.)
-- -----------------------------------------------------------------------------
create table public.delivery_documents (
  id          uuid primary key default gen_random_uuid(),
  dispatch_id uuid not null references public.dispatches(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,
  doc_type    text not null default 'other',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid,
  updated_by  uuid,
  constraint delivery_documents_unique unique (dispatch_id, document_id),
  constraint delivery_documents_type_chk check (doc_type in
    ('packing_list','eway_bill','pod','lr','insurance','invoice_copy','other'))
);

comment on table public.delivery_documents is
  'Documents attached to a dispatch: packing list, e-way bill, proof of delivery, LR, insurance, invoice copy.';

create index delivery_documents_dispatch_idx on public.delivery_documents (dispatch_id);

-- -----------------------------------------------------------------------------
-- invoices : customer invoice
-- -----------------------------------------------------------------------------
create table public.invoices (
  id                uuid primary key default gen_random_uuid(),
  invoice_no        text not null unique,
  invoice_date      date not null default current_date,
  customer_id       uuid not null references public.customers(id) on delete restrict,
  customer_order_id uuid references public.customer_orders(id) on delete set null,
  dispatch_id       uuid references public.dispatches(id) on delete set null,
  currency          text not null default 'INR',
  subtotal          numeric(14,2) not null default 0,
  tax_total         numeric(14,2) not null default 0,
  grand_total       numeric(14,2) not null default 0,
  due_date          date,
  status            text not null default 'draft',
  notes             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid,
  updated_by        uuid,
  constraint invoices_status_chk check (status in
    ('draft','issued','partially_paid','paid','overdue','cancelled','void')),
  constraint invoices_due_chk check (due_date is null or due_date >= invoice_date),
  constraint invoices_money_chk check (subtotal >= 0 and tax_total >= 0 and grand_total >= 0)
);

comment on table public.invoices is
  'Customer invoice. Totals are recalculated from invoice_items. A paid/void invoice may not be edited.';
comment on column public.invoices.status is
  'draft | issued | partially_paid | paid | overdue | cancelled | void. Derived from recorded payments where possible.';

create index invoices_customer_idx on public.invoices (customer_id);
create index invoices_status_idx on public.invoices (status);
create index invoices_due_idx on public.invoices (due_date);

-- -----------------------------------------------------------------------------
-- invoice_items
-- -----------------------------------------------------------------------------
create table public.invoice_items (
  id            uuid primary key default gen_random_uuid(),
  invoice_id    uuid not null references public.invoices(id) on delete cascade,
  line_no       integer not null,
  product_id    uuid references public.products(id) on delete set null,
  order_item_id uuid references public.order_items(id) on delete set null,
  description   text not null,
  quantity      numeric(14,3) not null,
  unit          text not null default 'NO',
  unit_price    numeric(14,2) not null default 0,
  discount_pct  numeric(6,2) not null default 0,
  tax_pct       numeric(6,2) not null default 0,
  line_total    numeric(14,2) generated always as
    (round(quantity * unit_price * (1 - discount_pct / 100) * (1 + tax_pct / 100), 2)) stored,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid,
  updated_by    uuid,
  constraint invoice_items_unique unique (invoice_id, line_no),
  constraint invoice_items_qty_chk check (quantity > 0),
  constraint invoice_items_price_chk check (unit_price >= 0),
  constraint invoice_items_desc_not_blank check (btrim(description) <> '')
);

comment on table public.invoice_items is
  'Line items of an invoice. Included so an invoice reconciles to its lines (the totals trigger depends on it).';

create index invoice_items_invoice_idx on public.invoice_items (invoice_id);

-- -----------------------------------------------------------------------------
-- payments : both customer receipts and OEM payments
-- -----------------------------------------------------------------------------
create table public.payments (
  id                uuid primary key default gen_random_uuid(),
  payment_no        text not null unique,
  payment_type      text not null default 'customer_receipt',
  invoice_id        uuid references public.invoices(id) on delete set null,
  purchase_order_id uuid references public.purchase_orders(id) on delete set null,
  customer_id       uuid references public.customers(id) on delete set null,
  oem_id            uuid references public.oems(id) on delete set null,
  payment_date      date not null default current_date,
  amount            numeric(14,2) not null,
  currency          text not null default 'INR',
  mode              text,
  reference         text,
  notes             text,
  recorded_by       uuid references public.users(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid,
  updated_by        uuid,
  constraint payments_type_chk check (payment_type in ('customer_receipt','oem_payment')),
  constraint payments_amount_chk check (amount > 0),
  constraint payments_mode_chk check (mode is null or mode in
    ('neft','rtgs','upi','cheque','cash','card','other')),
  constraint payments_target_chk check (
    (payment_type = 'customer_receipt' and invoice_id is not null)
    or (payment_type = 'oem_payment' and purchase_order_id is not null)
  )
);

comment on table public.payments is
  'Money movements: customer_receipt (against an invoice) and oem_payment (against a purchase order). One table keeps dr/cr comparable.';
comment on column public.payments.payment_type is 'customer_receipt | oem_payment.';
comment on column public.payments.reference is 'Bank/UTR/cheque reference. Required in practice for reconciliation.';

create index payments_invoice_idx on public.payments (invoice_id);
create index payments_po_idx on public.payments (purchase_order_id);
create index payments_date_idx on public.payments (payment_date);

-- -----------------------------------------------------------------------------
-- warranties
-- -----------------------------------------------------------------------------
create table public.warranties (
  id                uuid primary key default gen_random_uuid(),
  customer_id       uuid references public.customers(id) on delete set null,
  customer_order_id uuid references public.customer_orders(id) on delete set null,
  order_item_id     uuid references public.order_items(id) on delete set null,
  product_id        uuid references public.products(id) on delete set null,
  warranty_type     text not null default 'standard',
  start_date        date,
  end_date          date,
  terms             text,
  status            text not null default 'active',
  claim_notes       text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid,
  updated_by        uuid,
  constraint warranties_status_chk check (status in ('active','expired','void','claimed')),
  constraint warranties_dates_chk check (end_date is null or start_date is null or end_date >= start_date)
);

comment on table public.warranties is
  'Warranty / guarantee coverage per customer order item, product or customer. Drives renewal and claim tracking.';

create index warranties_customer_idx on public.warranties (customer_id);
create index warranties_end_idx on public.warranties (end_date);
create index warranties_status_idx on public.warranties (status);

-- ============================== 0011_ops.sql ==============================
-- =============================================================================
-- 0011_ops.sql
-- Operational tables: tasks, notifications and the append-only audit log.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- tasks : follow-ups / to-dos, optionally linked to any business record
-- -----------------------------------------------------------------------------
create table public.tasks (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  description  text,
  entity_table text,
  entity_id    uuid,
  assigned_to  uuid references public.users(id) on delete set null,
  due_date     date,
  priority     text not null default 'medium',
  status       text not null default 'open',
  completed_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid,
  updated_by   uuid,
  constraint tasks_status_chk check (status in ('open','in_progress','blocked','done','cancelled')),
  constraint tasks_priority_chk check (priority in ('low','medium','high','critical')),
  constraint tasks_title_not_blank check (btrim(title) <> '')
);

comment on table public.tasks is
  'Follow-up tasks. Optionally linked to any business record via entity_table/entity_id; assigned to a user with a due date.';

create index tasks_assignee_idx on public.tasks (assigned_to);
create index tasks_status_idx on public.tasks (status);
create index tasks_due_idx on public.tasks (due_date);
create index tasks_entity_idx on public.tasks (entity_table, entity_id);

-- -----------------------------------------------------------------------------
-- notifications : in-app / email notifications per user
-- -----------------------------------------------------------------------------
create table public.notifications (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.users(id) on delete cascade,
  title        text not null,
  body         text,
  entity_table text,
  entity_id    uuid,
  channel      text not null default 'in_app',
  status       text not null default 'unread',
  read_at      timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid,
  updated_by   uuid,
  constraint notifications_channel_chk check (channel in ('in_app','email')),
  constraint notifications_status_chk check (status in ('unread','read','archived')),
  constraint notifications_title_not_blank check (btrim(title) <> '')
);

comment on table public.notifications is
  'Notifications delivered to a user (in-app or email), optionally linked to the record that caused them.';
comment on column public.notifications.status is 'unread | read | archived.';

create index notifications_user_idx on public.notifications (user_id, status);
create index notifications_created_idx on public.notifications (created_at desc);

-- -----------------------------------------------------------------------------
-- audit_logs : append-only change history. No updated_at by design.
-- Written by app.audit_row() (SECURITY DEFINER). No INSERT/UPDATE/DELETE policy
-- is granted to normal roles.
-- -----------------------------------------------------------------------------
create table public.audit_logs (
  id            uuid primary key default gen_random_uuid(),
  actor_user_id uuid references public.users(id) on delete set null,
  action        text not null,
  entity_table  text not null,
  entity_id     uuid,
  before_data   jsonb,
  after_data    jsonb,
  ip_address    inet,
  created_at    timestamptz not null default now(),
  constraint audit_logs_action_chk check (action in
    ('insert','update','delete','approve','submit','receive','dispatch','login','export','other'))
);

comment on table public.audit_logs is
  'Append-only audit trail: who changed what, when, and the before/after values. Written only by trigger.';
comment on column public.audit_logs.before_data is 'Row image before the change (null on insert).';
comment on column public.audit_logs.after_data is 'Row image after the change (null on delete).';

create index audit_logs_entity_idx on public.audit_logs (entity_table, entity_id, created_at desc);
create index audit_logs_actor_idx on public.audit_logs (actor_user_id, created_at desc);
create index audit_logs_created_idx on public.audit_logs (created_at desc);

-- ============================== 0012_rls.sql ==============================
-- =============================================================================
-- 0012_rls.sql
-- Row Level Security: default deny, role-based access, append-only audit.
-- Assumes the Supabase roles anon, authenticated and service_role already exist.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Privileges. RLS is the row-level guard; these are the table-level grants.
-- anon (logged out) gets nothing. authenticated gets the baseline, then RLS
-- decides row by row. service_role bypasses RLS (Supabase's server key).
-- -----------------------------------------------------------------------------
grant usage on schema public to authenticated, service_role;
revoke all on all tables in schema public from anon;
revoke all on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to authenticated, service_role;
alter default privileges in schema public grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public grant all on tables to service_role;

-- -----------------------------------------------------------------------------
-- Enable RLS on every table. With RLS on and no matching policy: no access.
-- -----------------------------------------------------------------------------
alter table public.users                 enable row level security;
alter table public.roles                 enable row level security;
alter table public.user_roles            enable row level security;
alter table public.customers             enable row level security;
alter table public.customer_contacts     enable row level security;
alter table public.products              enable row level security;
alter table public.product_specifications enable row level security;
alter table public.oems                  enable row level security;
alter table public.oem_contacts          enable row level security;
alter table public.oem_products          enable row level security;
alter table public.oem_price_history     enable row level security;
alter table public.documents             enable row level security;
alter table public.tenders               enable row level security;
alter table public.tender_documents      enable row level security;
alter table public.tender_requirements   enable row level security;
alter table public.opportunities         enable row level security;
alter table public.requirements          enable row level security;
alter table public.compliance_items      enable row level security;
alter table public.quotations            enable row level security;
alter table public.quotation_items       enable row level security;
alter table public.quotation_approvals   enable row level security;
alter table public.customer_orders       enable row level security;
alter table public.order_items           enable row level security;
alter table public.purchase_requests     enable row level security;
alter table public.purchase_request_items enable row level security;
alter table public.purchase_orders       enable row level security;
alter table public.purchase_order_items  enable row level security;
alter table public.material_receipts     enable row level security;
alter table public.material_receipt_items enable row level security;
alter table public.pdi_records           enable row level security;
alter table public.pdi_items             enable row level security;
alter table public.dispatches            enable row level security;
alter table public.dispatch_items        enable row level security;
alter table public.delivery_documents    enable row level security;
alter table public.invoices              enable row level security;
alter table public.invoice_items         enable row level security;
alter table public.payments              enable row level security;
alter table public.warranties            enable row level security;
alter table public.tasks                 enable row level security;
alter table public.notifications         enable row level security;
alter table public.audit_logs            enable row level security;

-- =============================================================================
-- IDENTITY / ACCESS
-- =============================================================================
create policy users_select on public.users for select to authenticated
  using (id = app.current_user_id() or app.has_any_role(array['admin','management']));
create policy users_insert on public.users for insert to authenticated
  with check (app.is_admin());
create policy users_update on public.users for update to authenticated
  using (app.is_admin()) with check (app.is_admin());
create policy users_delete on public.users for delete to authenticated
  using (app.is_admin());

create policy roles_select on public.roles for select to authenticated
  using (app.is_staff());
create policy roles_insert on public.roles for insert to authenticated
  with check (app.is_admin());
create policy roles_update on public.roles for update to authenticated
  using (app.is_admin()) with check (app.is_admin());
create policy roles_delete on public.roles for delete to authenticated
  using (app.is_admin());

create policy user_roles_select on public.user_roles for select to authenticated
  using (user_id = app.current_user_id() or app.has_any_role(array['admin','management']));
create policy user_roles_insert on public.user_roles for insert to authenticated
  with check (app.is_admin());
create policy user_roles_update on public.user_roles for update to authenticated
  using (app.is_admin()) with check (app.is_admin());
create policy user_roles_delete on public.user_roles for delete to authenticated
  using (app.is_admin());

-- =============================================================================
-- MASTERS  (read: all staff)  (write: admin, sales, procurement)
-- =============================================================================
create policy customers_select on public.customers for select to authenticated using (app.is_staff());
create policy customers_insert on public.customers for insert to authenticated with check (app.has_any_role(array['admin','sales','procurement']));
create policy customers_update on public.customers for update to authenticated using (app.has_any_role(array['admin','sales','procurement'])) with check (app.has_any_role(array['admin','sales','procurement']));
create policy customers_delete on public.customers for delete to authenticated using (app.is_admin());

create policy customer_contacts_select on public.customer_contacts for select to authenticated using (app.is_staff());
create policy customer_contacts_insert on public.customer_contacts for insert to authenticated with check (app.has_any_role(array['admin','sales','procurement']));
create policy customer_contacts_update on public.customer_contacts for update to authenticated using (app.has_any_role(array['admin','sales','procurement'])) with check (app.has_any_role(array['admin','sales','procurement']));
create policy customer_contacts_delete on public.customer_contacts for delete to authenticated using (app.is_admin());

create policy products_select on public.products for select to authenticated using (app.is_staff());
create policy products_insert on public.products for insert to authenticated with check (app.has_any_role(array['admin','sales','procurement','technical']));
create policy products_update on public.products for update to authenticated using (app.has_any_role(array['admin','sales','procurement','technical'])) with check (app.has_any_role(array['admin','sales','procurement','technical']));
create policy products_delete on public.products for delete to authenticated using (app.is_admin());

create policy product_specifications_select on public.product_specifications for select to authenticated using (app.is_staff());
create policy product_specifications_insert on public.product_specifications for insert to authenticated with check (app.has_any_role(array['admin','technical','procurement']));
create policy product_specifications_update on public.product_specifications for update to authenticated using (app.has_any_role(array['admin','technical','procurement'])) with check (app.has_any_role(array['admin','technical','procurement']));
create policy product_specifications_delete on public.product_specifications for delete to authenticated using (app.is_admin());

create policy oems_select on public.oems for select to authenticated using (app.is_staff());
create policy oems_insert on public.oems for insert to authenticated with check (app.has_any_role(array['admin','procurement']));
create policy oems_update on public.oems for update to authenticated using (app.has_any_role(array['admin','procurement'])) with check (app.has_any_role(array['admin','procurement']));
create policy oems_delete on public.oems for delete to authenticated using (app.is_admin());

create policy oem_contacts_select on public.oem_contacts for select to authenticated using (app.is_staff());
create policy oem_contacts_insert on public.oem_contacts for insert to authenticated with check (app.has_any_role(array['admin','procurement']));
create policy oem_contacts_update on public.oem_contacts for update to authenticated using (app.has_any_role(array['admin','procurement'])) with check (app.has_any_role(array['admin','procurement']));
create policy oem_contacts_delete on public.oem_contacts for delete to authenticated using (app.is_admin());

create policy oem_products_select on public.oem_products for select to authenticated using (app.is_staff());
create policy oem_products_insert on public.oem_products for insert to authenticated with check (app.has_any_role(array['admin','procurement','technical']));
create policy oem_products_update on public.oem_products for update to authenticated using (app.has_any_role(array['admin','procurement','technical'])) with check (app.has_any_role(array['admin','procurement','technical']));
create policy oem_products_delete on public.oem_products for delete to authenticated using (app.is_admin());

create policy oem_price_history_select on public.oem_price_history for select to authenticated using (app.is_staff());
create policy oem_price_history_insert on public.oem_price_history for insert to authenticated with check (app.has_any_role(array['admin','procurement','sales']));
create policy oem_price_history_update on public.oem_price_history for update to authenticated using (app.has_any_role(array['admin','procurement','sales'])) with check (app.has_any_role(array['admin','procurement','sales']));
create policy oem_price_history_delete on public.oem_price_history for delete to authenticated using (app.is_admin());

-- =============================================================================
-- DOCUMENTS  (read: staff, but controlled/itar restricted)
-- =============================================================================
create policy documents_select on public.documents for select to authenticated
  using (
    app.is_staff()
    and (
      classification in ('unclassified','internal','confidential')
      or app.has_any_role(array['admin','management','technical','qa'])
    )
  );
create policy documents_insert on public.documents for insert to authenticated
  with check (app.is_staff());
create policy documents_update on public.documents for update to authenticated
  using (app.is_staff()) with check (app.is_staff());
create policy documents_delete on public.documents for delete to authenticated
  using (app.is_admin());

-- =============================================================================
-- TENDERS / OPPORTUNITIES
-- =============================================================================
create policy tenders_select on public.tenders for select to authenticated using (app.is_staff());
create policy tenders_insert on public.tenders for insert to authenticated with check (app.has_any_role(array['admin','sales']));
create policy tenders_update on public.tenders for update to authenticated using (app.has_any_role(array['admin','sales','technical'])) with check (app.has_any_role(array['admin','sales','technical']));
create policy tenders_delete on public.tenders for delete to authenticated using (app.is_admin());

create policy tender_documents_select on public.tender_documents for select to authenticated using (app.is_staff());
create policy tender_documents_insert on public.tender_documents for insert to authenticated with check (app.has_any_role(array['admin','sales','technical']));
create policy tender_documents_update on public.tender_documents for update to authenticated using (app.has_any_role(array['admin','sales','technical'])) with check (app.has_any_role(array['admin','sales','technical']));
create policy tender_documents_delete on public.tender_documents for delete to authenticated using (app.is_admin());

create policy tender_requirements_select on public.tender_requirements for select to authenticated using (app.is_staff());
create policy tender_requirements_insert on public.tender_requirements for insert to authenticated with check (app.has_any_role(array['admin','sales','technical']));
create policy tender_requirements_update on public.tender_requirements for update to authenticated using (app.has_any_role(array['admin','sales','technical'])) with check (app.has_any_role(array['admin','sales','technical']));
create policy tender_requirements_delete on public.tender_requirements for delete to authenticated using (app.is_admin());

create policy opportunities_select on public.opportunities for select to authenticated using (app.is_staff());
create policy opportunities_insert on public.opportunities for insert to authenticated with check (app.has_any_role(array['admin','sales']));
create policy opportunities_update on public.opportunities for update to authenticated using (app.has_any_role(array['admin','sales'])) with check (app.has_any_role(array['admin','sales']));
create policy opportunities_delete on public.opportunities for delete to authenticated using (app.is_admin());

create policy requirements_select on public.requirements for select to authenticated using (app.is_staff());
create policy requirements_insert on public.requirements for insert to authenticated with check (app.has_any_role(array['admin','sales','technical']));
create policy requirements_update on public.requirements for update to authenticated using (app.has_any_role(array['admin','sales','technical'])) with check (app.has_any_role(array['admin','sales','technical']));
create policy requirements_delete on public.requirements for delete to authenticated using (app.is_admin());

create policy compliance_items_select on public.compliance_items for select to authenticated using (app.is_staff());
create policy compliance_items_insert on public.compliance_items for insert to authenticated with check (app.has_any_role(array['admin','sales','technical','qa']));
create policy compliance_items_update on public.compliance_items for update to authenticated using (app.has_any_role(array['admin','sales','technical','qa'])) with check (app.has_any_role(array['admin','sales','technical','qa']));
create policy compliance_items_delete on public.compliance_items for delete to authenticated using (app.is_admin());

-- =============================================================================
-- QUOTATIONS  (approval is management/admin only)
-- =============================================================================
create policy quotations_select on public.quotations for select to authenticated using (app.is_staff());
create policy quotations_insert on public.quotations for insert to authenticated with check (app.has_any_role(array['admin','sales']));
create policy quotations_update on public.quotations for update to authenticated using (app.has_any_role(array['admin','sales','management'])) with check (app.has_any_role(array['admin','sales','management']));
create policy quotations_delete on public.quotations for delete to authenticated using (app.is_admin());

create policy quotation_items_select on public.quotation_items for select to authenticated using (app.is_staff());
create policy quotation_items_insert on public.quotation_items for insert to authenticated with check (app.has_any_role(array['admin','sales']));
create policy quotation_items_update on public.quotation_items for update to authenticated using (app.has_any_role(array['admin','sales'])) with check (app.has_any_role(array['admin','sales']));
create policy quotation_items_delete on public.quotation_items for delete to authenticated using (app.is_admin());

create policy quotation_approvals_select on public.quotation_approvals for select to authenticated using (app.is_staff());
create policy quotation_approvals_insert on public.quotation_approvals for insert to authenticated with check (app.has_any_role(array['admin','management']));
create policy quotation_approvals_update on public.quotation_approvals for update to authenticated using (app.has_any_role(array['admin','management'])) with check (app.has_any_role(array['admin','management']));
create policy quotation_approvals_delete on public.quotation_approvals for delete to authenticated using (app.is_admin());

-- =============================================================================
-- CUSTOMER ORDERS
-- =============================================================================
create policy customer_orders_select on public.customer_orders for select to authenticated using (app.is_staff());
create policy customer_orders_insert on public.customer_orders for insert to authenticated with check (app.has_any_role(array['admin','sales']));
create policy customer_orders_update on public.customer_orders for update to authenticated using (app.has_any_role(array['admin','sales'])) with check (app.has_any_role(array['admin','sales']));
create policy customer_orders_delete on public.customer_orders for delete to authenticated using (app.is_admin());

create policy order_items_select on public.order_items for select to authenticated using (app.is_staff());
create policy order_items_insert on public.order_items for insert to authenticated with check (app.has_any_role(array['admin','sales']));
create policy order_items_update on public.order_items for update to authenticated using (app.has_any_role(array['admin','sales'])) with check (app.has_any_role(array['admin','sales']));
create policy order_items_delete on public.order_items for delete to authenticated using (app.is_admin());

-- =============================================================================
-- PROCUREMENT
-- =============================================================================
create policy purchase_requests_select on public.purchase_requests for select to authenticated using (app.is_staff());
create policy purchase_requests_insert on public.purchase_requests for insert to authenticated with check (app.has_any_role(array['admin','sales','procurement']));
create policy purchase_requests_update on public.purchase_requests for update to authenticated using (app.has_any_role(array['admin','sales','procurement'])) with check (app.has_any_role(array['admin','sales','procurement']));
create policy purchase_requests_delete on public.purchase_requests for delete to authenticated using (app.is_admin());

create policy purchase_request_items_select on public.purchase_request_items for select to authenticated using (app.is_staff());
create policy purchase_request_items_insert on public.purchase_request_items for insert to authenticated with check (app.has_any_role(array['admin','sales','procurement']));
create policy purchase_request_items_update on public.purchase_request_items for update to authenticated using (app.has_any_role(array['admin','sales','procurement'])) with check (app.has_any_role(array['admin','sales','procurement']));
create policy purchase_request_items_delete on public.purchase_request_items for delete to authenticated using (app.is_admin());

create policy purchase_orders_select on public.purchase_orders for select to authenticated using (app.is_staff());
create policy purchase_orders_insert on public.purchase_orders for insert to authenticated with check (app.has_any_role(array['admin','procurement']));
create policy purchase_orders_update on public.purchase_orders for update to authenticated using (app.has_any_role(array['admin','procurement','management'])) with check (app.has_any_role(array['admin','procurement','management']));
create policy purchase_orders_delete on public.purchase_orders for delete to authenticated using (app.is_admin());

create policy purchase_order_items_select on public.purchase_order_items for select to authenticated using (app.is_staff());
create policy purchase_order_items_insert on public.purchase_order_items for insert to authenticated with check (app.has_any_role(array['admin','procurement']));
create policy purchase_order_items_update on public.purchase_order_items for update to authenticated using (app.has_any_role(array['admin','procurement'])) with check (app.has_any_role(array['admin','procurement']));
create policy purchase_order_items_delete on public.purchase_order_items for delete to authenticated using (app.is_admin());

-- =============================================================================
-- RECEIPTS / INSPECTION
-- =============================================================================
create policy material_receipts_select on public.material_receipts for select to authenticated using (app.is_staff());
create policy material_receipts_insert on public.material_receipts for insert to authenticated with check (app.has_any_role(array['admin','stores']));
create policy material_receipts_update on public.material_receipts for update to authenticated using (app.has_any_role(array['admin','stores'])) with check (app.has_any_role(array['admin','stores']));
create policy material_receipts_delete on public.material_receipts for delete to authenticated using (app.is_admin());

create policy material_receipt_items_select on public.material_receipt_items for select to authenticated using (app.is_staff());
create policy material_receipt_items_insert on public.material_receipt_items for insert to authenticated with check (app.has_any_role(array['admin','stores']));
create policy material_receipt_items_update on public.material_receipt_items for update to authenticated using (app.has_any_role(array['admin','stores'])) with check (app.has_any_role(array['admin','stores']));
create policy material_receipt_items_delete on public.material_receipt_items for delete to authenticated using (app.is_admin());

create policy pdi_records_select on public.pdi_records for select to authenticated using (app.is_staff());
create policy pdi_records_insert on public.pdi_records for insert to authenticated with check (app.has_any_role(array['admin','qa']));
create policy pdi_records_update on public.pdi_records for update to authenticated using (app.has_any_role(array['admin','qa'])) with check (app.has_any_role(array['admin','qa']));
create policy pdi_records_delete on public.pdi_records for delete to authenticated using (app.is_admin());

create policy pdi_items_select on public.pdi_items for select to authenticated using (app.is_staff());
create policy pdi_items_insert on public.pdi_items for insert to authenticated with check (app.has_any_role(array['admin','qa']));
create policy pdi_items_update on public.pdi_items for update to authenticated using (app.has_any_role(array['admin','qa'])) with check (app.has_any_role(array['admin','qa']));
create policy pdi_items_delete on public.pdi_items for delete to authenticated using (app.is_admin());

-- =============================================================================
-- DISPATCH
-- =============================================================================
create policy dispatches_select on public.dispatches for select to authenticated using (app.is_staff());
create policy dispatches_insert on public.dispatches for insert to authenticated with check (app.has_any_role(array['admin','logistics']));
create policy dispatches_update on public.dispatches for update to authenticated using (app.has_any_role(array['admin','logistics'])) with check (app.has_any_role(array['admin','logistics']));
create policy dispatches_delete on public.dispatches for delete to authenticated using (app.is_admin());

create policy dispatch_items_select on public.dispatch_items for select to authenticated using (app.is_staff());
create policy dispatch_items_insert on public.dispatch_items for insert to authenticated with check (app.has_any_role(array['admin','logistics']));
create policy dispatch_items_update on public.dispatch_items for update to authenticated using (app.has_any_role(array['admin','logistics'])) with check (app.has_any_role(array['admin','logistics']));
create policy dispatch_items_delete on public.dispatch_items for delete to authenticated using (app.is_admin());

create policy delivery_documents_select on public.delivery_documents for select to authenticated using (app.is_staff());
create policy delivery_documents_insert on public.delivery_documents for insert to authenticated with check (app.has_any_role(array['admin','logistics']));
create policy delivery_documents_update on public.delivery_documents for update to authenticated using (app.has_any_role(array['admin','logistics'])) with check (app.has_any_role(array['admin','logistics']));
create policy delivery_documents_delete on public.delivery_documents for delete to authenticated using (app.is_admin());

-- =============================================================================
-- FINANCE
-- =============================================================================
create policy invoices_select on public.invoices for select to authenticated using (app.is_staff());
create policy invoices_insert on public.invoices for insert to authenticated with check (app.has_any_role(array['admin','accounts']));
create policy invoices_update on public.invoices for update to authenticated using (app.has_any_role(array['admin','accounts'])) with check (app.has_any_role(array['admin','accounts']));
create policy invoices_delete on public.invoices for delete to authenticated using (app.is_admin());

create policy invoice_items_select on public.invoice_items for select to authenticated using (app.is_staff());
create policy invoice_items_insert on public.invoice_items for insert to authenticated with check (app.has_any_role(array['admin','accounts']));
create policy invoice_items_update on public.invoice_items for update to authenticated using (app.has_any_role(array['admin','accounts'])) with check (app.has_any_role(array['admin','accounts']));
create policy invoice_items_delete on public.invoice_items for delete to authenticated using (app.is_admin());

create policy payments_select on public.payments for select to authenticated using (app.is_staff());
create policy payments_insert on public.payments for insert to authenticated with check (app.has_any_role(array['admin','accounts']));
create policy payments_update on public.payments for update to authenticated using (app.has_any_role(array['admin','accounts'])) with check (app.has_any_role(array['admin','accounts']));
create policy payments_delete on public.payments for delete to authenticated using (app.is_admin());

create policy warranties_select on public.warranties for select to authenticated using (app.is_staff());
create policy warranties_insert on public.warranties for insert to authenticated with check (app.has_any_role(array['admin','accounts','qa','sales']));
create policy warranties_update on public.warranties for update to authenticated using (app.has_any_role(array['admin','accounts','qa','sales'])) with check (app.has_any_role(array['admin','accounts','qa','sales']));
create policy warranties_delete on public.warranties for delete to authenticated using (app.is_admin());

-- =============================================================================
-- OPS
-- =============================================================================
create policy tasks_select on public.tasks for select to authenticated using (app.is_staff());
create policy tasks_insert on public.tasks for insert to authenticated with check (app.is_staff());
create policy tasks_update on public.tasks for update to authenticated
  using (assigned_to = app.current_user_id() or app.has_any_role(array['admin','management']))
  with check (assigned_to = app.current_user_id() or app.has_any_role(array['admin','management']));
create policy tasks_delete on public.tasks for delete to authenticated using (app.is_admin());

create policy notifications_select on public.notifications for select to authenticated
  using (user_id = app.current_user_id() or app.has_any_role(array['admin','management']));
create policy notifications_insert on public.notifications for insert to authenticated
  with check (app.has_any_role(array['admin','management']));
create policy notifications_update on public.notifications for update to authenticated
  using (user_id = app.current_user_id() or app.has_any_role(array['admin','management']))
  with check (user_id = app.current_user_id() or app.has_any_role(array['admin','management']));
create policy notifications_delete on public.notifications for delete to authenticated using (app.is_admin());

-- audit_logs: readable by admin/management/accounts, append-only (no write policies).
create policy audit_logs_select on public.audit_logs for select to authenticated
  using (app.has_any_role(array['admin','management','accounts']));

-- ============================== 0013_triggers.sql ==============================
-- =============================================================================
-- 0013_triggers.sql
-- Attaches behaviour to the tables:
--   * updated_at maintenance on every table that has that column
--   * append-only audit on every business table
--   * header totals recalculated from line items
--   * received_qty / delivered_qty kept true to the receipt / dispatch lines
--   * the PDI gate that blocks dispatch of uninspected material
--   * segregation-of-duties rules
--   * invoice lock once paid/void, and invoice status derived from payments
--   * audit column defaults (created_by / updated_by = current user)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Audit column defaults: created_by / updated_by default to the current user.
-- -----------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select table_name from information_schema.columns
     where table_schema = 'public' and column_name = 'created_by'
  loop
    execute format('alter table public.%I alter column created_by set default app.current_user_id()', r.table_name);
  end loop;

  for r in
    select table_name from information_schema.columns
     where table_schema = 'public' and column_name = 'updated_by'
  loop
    execute format('alter table public.%I alter column updated_by set default app.current_user_id()', r.table_name);
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- updated_at triggers
-- -----------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select c.table_name
      from information_schema.columns c
      join information_schema.tables t
        on t.table_schema = c.table_schema and t.table_name = c.table_name
     where c.table_schema = 'public'
       and c.column_name = 'updated_at'
       and t.table_type = 'BASE TABLE'
  loop
    execute format('drop trigger if exists %I on public.%I', 'trg_touch_' || r.table_name, r.table_name);
    execute format('create trigger %I before update on public.%I for each row execute function app.set_updated_at()',
                   'trg_touch_' || r.table_name, r.table_name);
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- Append-only audit triggers (every business table except audit_logs itself)
-- -----------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select table_name from information_schema.tables
     where table_schema = 'public' and table_type = 'BASE TABLE' and table_name <> 'audit_logs'
  loop
    execute format('drop trigger if exists %I on public.%I', 'trg_audit_' || r.table_name, r.table_name);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.audit_row()',
                   'trg_audit_' || r.table_name, r.table_name);
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- Header totals from line items
-- -----------------------------------------------------------------------------
create trigger trg_totals_quotation
  after insert or update or delete on public.quotation_items
  for each row execute function app.recalc_parent_totals('quotations', 'quotation_id');

create trigger trg_totals_customer_order
  after insert or update or delete on public.order_items
  for each row execute function app.recalc_parent_totals('customer_orders', 'customer_order_id');

create trigger trg_totals_purchase_order
  after insert or update or delete on public.purchase_order_items
  for each row execute function app.recalc_parent_totals('purchase_orders', 'purchase_order_id');

create trigger trg_totals_invoice
  after insert or update or delete on public.invoice_items
  for each row execute function app.recalc_parent_totals('invoices', 'invoice_id');

-- -----------------------------------------------------------------------------
-- received_qty: keep purchase_order_items true to material_receipt_items
-- and roll the parent purchase_order status up.
-- -----------------------------------------------------------------------------
create or replace function app.recalc_po_item_received()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_item uuid;
  v_po   uuid;
begin
  v_item := coalesce(new.purchase_order_item_id, old.purchase_order_item_id);
  if v_item is null then return null; end if;

  update public.purchase_order_items p
     set received_qty = s.q,
         status = case
                    when s.q <= 0 then 'open'
                    when s.q >= p.quantity then 'received'
                    else 'partially_received'
                  end,
         updated_at = now()
    from (select coalesce(sum(qty_received), 0) q
            from public.material_receipt_items
           where purchase_order_item_id = v_item) s
   where p.id = v_item;

  select purchase_order_id into v_po from public.purchase_order_items where id = v_item;

  update public.purchase_orders po
     set status = case
                    when exists (select 1 from public.purchase_order_items i
                                  where i.purchase_order_id = po.id and i.status = 'partially_received')
                      then 'partially_received'
                    when exists (select 1 from public.purchase_order_items i
                                  where i.purchase_order_id = po.id and i.status not in ('received','cancelled'))
                      then po.status
                    else 'received'
                  end,
         updated_at = now()
   where po.id = v_po and po.status not in ('cancelled','closed');

  return null;
end;
$$;

create trigger trg_po_item_received
  after insert or update or delete on public.material_receipt_items
  for each row execute function app.recalc_po_item_received();

-- -----------------------------------------------------------------------------
-- delivered_qty: keep order_items true to dispatch_items and roll the parent
-- customer_order status up.
-- -----------------------------------------------------------------------------
create or replace function app.recalc_order_item_delivered()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_item  uuid;
  v_order uuid;
begin
  v_item := coalesce(new.order_item_id, old.order_item_id);
  if v_item is null then return null; end if;

  update public.order_items o
     set delivered_qty = s.q,
         status = case
                    when s.q <= 0 then 'open'
                    when s.q >= o.quantity then 'delivered'
                    else 'partially_delivered'
                  end,
         updated_at = now()
    from (select coalesce(sum(quantity), 0) q
            from public.dispatch_items
           where order_item_id = v_item) s
   where o.id = v_item;

  select customer_order_id into v_order from public.order_items where id = v_item;

  update public.customer_orders co
     set status = case
                    when exists (select 1 from public.order_items i
                                  where i.customer_order_id = co.id and i.status = 'partially_delivered')
                      then 'partially_delivered'
                    when exists (select 1 from public.order_items i
                                  where i.customer_order_id = co.id and i.status not in ('delivered','cancelled'))
                      then co.status
                    else 'delivered'
                  end,
         updated_at = now()
   where co.id = v_order and co.status not in ('cancelled','closed','invoiced');

  return null;
end;
$$;

create trigger trg_order_item_delivered
  after insert or update or delete on public.dispatch_items
  for each row execute function app.recalc_order_item_delivered();

-- -----------------------------------------------------------------------------
-- PDI gate: an order line may only be dispatched once a PASSED PDI exists for it.
-- The chain is: dispatch_items -> order_items <- purchase_order_items <-
--              material_receipt_items <- pdi_items -> pdi_records.
-- -----------------------------------------------------------------------------
create or replace function app.enforce_pdi_before_dispatch()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_ok boolean;
begin
  select exists (
    select 1
      from public.pdi_items pi
      join public.pdi_records pr        on pr.id = pi.pdi_record_id
      join public.material_receipt_items mri on mri.id = pi.material_receipt_item_id
      join public.purchase_order_items  poi on poi.id = mri.purchase_order_item_id
     where poi.order_item_id = new.order_item_id
       and pr.result = 'pass'
       and pi.qty_passed > 0
  ) into v_ok;

  if not v_ok then
    raise exception
      'Cannot dispatch order line %: no passed PDI record exists for it', new.order_item_id
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger trg_dispatch_requires_pdi
  before insert or update on public.dispatch_items
  for each row execute function app.enforce_pdi_before_dispatch();

-- -----------------------------------------------------------------------------
-- Segregation of duties:
--   * the invoice creator may not record the payment for that invoice
--   * the PO creator may not receive the goods for that PO
-- Both also default the actor column to the current user.
-- -----------------------------------------------------------------------------
create or replace function app.segregation_payment()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_inv_creator uuid;
begin
  new.recorded_by := coalesce(new.recorded_by, app.current_user_id());

  if new.payment_type = 'customer_receipt' and new.invoice_id is not null then
    select created_by into v_inv_creator from public.invoices where id = new.invoice_id;
    if v_inv_creator is not null and v_inv_creator = new.recorded_by then
      raise exception 'Segregation of duties: the user who created invoice % cannot record its payment', new.invoice_id
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_segregation_payment
  before insert or update on public.payments
  for each row execute function app.segregation_payment();

create or replace function app.segregation_receipt()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_po_creator uuid;
begin
  new.received_by := coalesce(new.received_by, app.current_user_id());

  if new.purchase_order_id is not null then
    select created_by into v_po_creator from public.purchase_orders where id = new.purchase_order_id;
    if v_po_creator is not null and v_po_creator = new.received_by then
      raise exception 'Segregation of duties: the user who created purchase order % cannot receive its goods', new.purchase_order_id
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_segregation_receipt
  before insert or update on public.material_receipts
  for each row execute function app.segregation_receipt();

-- -----------------------------------------------------------------------------
-- Invoice locking and derived status.
-- -----------------------------------------------------------------------------
create or replace function app.lock_paid_invoice()
returns trigger
language plpgsql
as $$
begin
  if old.status in ('paid','void') then
    if new.invoice_no   is distinct from old.invoice_no
       or new.grand_total is distinct from old.grand_total
       or new.subtotal    is distinct from old.subtotal
       or new.tax_total   is distinct from old.tax_total
       or new.customer_id is distinct from old.customer_id
       or new.invoice_date is distinct from old.invoice_date
    then
      raise exception 'Invoice % is % and cannot be edited', old.invoice_no, old.status
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_lock_paid_invoice
  before update on public.invoices
  for each row execute function app.lock_paid_invoice();

create or replace function app.recalc_invoice_status()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id     uuid;
  v_total  numeric(14,2);
  v_status text;
  v_paid   numeric(14,2);
begin
  v_id := case when tg_op = 'DELETE' then old.invoice_id else new.invoice_id end;
  if v_id is null then return null; end if;

  select grand_total, status into v_total, v_status from public.invoices where id = v_id;
  if v_status in ('void','cancelled') then return null; end if;

  select coalesce(sum(amount), 0) into v_paid
    from public.payments
   where invoice_id = v_id and payment_type = 'customer_receipt';

  update public.invoices
     set status = case
                    when v_total > 0 and v_paid >= v_total then 'paid'
                    when v_paid > 0 then 'partially_paid'
                    when v_status = 'draft' then 'draft'
                    else 'issued'
                  end,
         updated_at = now()
   where id = v_id;

  return null;
end;
$$;

create trigger trg_invoice_status
  after insert or update or delete on public.payments
  for each row execute function app.recalc_invoice_status();

-- ============================== 0014_tender_workflow.sql ==============================
-- =============================================================================
-- 0014_tender_workflow.sql
-- Tender Management module support.
--   * Replaces the tenders.status set with the agreed 13-stage pipeline.
--   * Adds tender_notes (a tender needs many timestamped notes, not one field).
--   * Enables RLS and attaches the standard triggers to the new table.
-- No other feature is added.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. New tender status pipeline (13 stages)
--    new | under_review | qualified | requirement_analysis | oem_pricing |
--    quotation_preparation | approval_pending | submitted | technical_evaluation |
--    commercial_evaluation | won | lost | cancelled
-- -----------------------------------------------------------------------------
alter table public.tenders drop constraint if exists tenders_status_chk;

update public.tenders set status = case status
  when 'draft'            then 'new'
  when 'received'         then 'new'
  when 'under_analysis'   then 'requirement_analysis'
  when 'rfq_sent'         then 'oem_pricing'
  when 'quoted'           then 'quotation_preparation'
  when 'submitted'        then 'submitted'
  when 'under_evaluation' then 'technical_evaluation'
  when 'won'              then 'won'
  when 'lost'             then 'lost'
  when 'cancelled'        then 'cancelled'
  when 'closed'           then 'won'
  else 'new'
end
where status not in (
  'new','under_review','qualified','requirement_analysis','oem_pricing',
  'quotation_preparation','approval_pending','submitted','technical_evaluation',
  'commercial_evaluation','won','lost','cancelled'
);

alter table public.tenders alter column status set default 'new';

alter table public.tenders add constraint tenders_status_chk check (status in (
  'new','under_review','qualified','requirement_analysis','oem_pricing',
  'quotation_preparation','approval_pending','submitted','technical_evaluation',
  'commercial_evaluation','won','lost','cancelled'
));

comment on column public.tenders.status is
  'Tender pipeline stage: new | under_review | qualified | requirement_analysis | oem_pricing | quotation_preparation | approval_pending | submitted | technical_evaluation | commercial_evaluation | won | lost | cancelled.';

-- -----------------------------------------------------------------------------
-- 2. tender_notes : many timestamped notes per tender
-- -----------------------------------------------------------------------------
create table public.tender_notes (
  id         uuid primary key default gen_random_uuid(),
  tender_id  uuid not null references public.tenders(id) on delete cascade,
  note       text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default app.current_user_id(),
  updated_by uuid default app.current_user_id(),
  constraint tender_notes_note_not_blank check (btrim(note) <> '')
);

comment on table public.tender_notes is
  'Free-text notes recorded against a tender, newest first, each with author and timestamp.';
comment on column public.tender_notes.note is 'The note text. Blank notes are rejected.';

create index tender_notes_tender_idx on public.tender_notes (tender_id, created_at desc);

-- -----------------------------------------------------------------------------
-- 3. RLS for the new table (same pattern as the rest of the schema)
-- -----------------------------------------------------------------------------
alter table public.tender_notes enable row level security;

create policy tender_notes_select on public.tender_notes for select to authenticated
  using (app.is_staff());
create policy tender_notes_insert on public.tender_notes for insert to authenticated
  with check (app.has_any_role(array['admin','sales','technical']));
create policy tender_notes_update on public.tender_notes for update to authenticated
  using (app.has_any_role(array['admin','sales','technical']))
  with check (app.has_any_role(array['admin','sales','technical']));
create policy tender_notes_delete on public.tender_notes for delete to authenticated
  using (app.is_admin());

-- -----------------------------------------------------------------------------
-- 4. Standard triggers for the new table (0013 only covered tables existing then)
-- -----------------------------------------------------------------------------
create trigger trg_touch_tender_notes
  before update on public.tender_notes
  for each row execute function app.set_updated_at();

create trigger trg_audit_tender_notes
  after insert or update or delete on public.tender_notes
  for each row execute function app.audit_row();

-- -----------------------------------------------------------------------------
-- 5. Let the tender team read tender-related activity history.
--    (Other audit rows stay restricted to admin / management / accounts.)
-- -----------------------------------------------------------------------------
create policy audit_logs_tender_activity on public.audit_logs for select to authenticated
  using (
    app.is_staff()
    and entity_table in ('tenders', 'tender_notes', 'tender_requirements')
  );

-- -----------------------------------------------------------------------------
-- 6. A names-only directory so the "Assign employee" dropdown works for
--    everyone, without exposing full user rows (users RLS stays strict).
--    The view is owned by the migration role and is read-only to the app.
-- -----------------------------------------------------------------------------
create or replace view public.user_directory as
  select id, full_name, designation
    from public.users
   where is_active;

comment on view public.user_directory is
  'Names-only directory of active users (id, full_name, designation) for assignee pickers.';

grant select on public.user_directory to authenticated;


-- ============================== 0015_quotation_module.sql ==============================
-- =============================================================================
-- 0015_quotation_module.sql
-- Quotation Management module support.
--   * Cost, logistics, other cost, margin and selling price at line and header.
--   * Commercial terms on the quotation (payment, delivery, warranty, validity).
--   * Technical compliance per line.
--   * Revisions (revision_of) ??? an approved quotation is never overwritten.
--   * Approval metadata and a guard against double approval.
--   * Immutability triggers: approved/submitted/won/lost quotations are frozen.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Quotation header: terms, revision link, approval metadata, cost totals.
-- -----------------------------------------------------------------------------
alter table public.quotations
  add column if not exists payment_terms        text,
  add column if not exists delivery_terms       text,
  add column if not exists warranty             text,
  add column if not exists revision_of          uuid references public.quotations(id) on delete set null,
  add column if not exists approved_by          uuid references public.users(id),
  add column if not exists approved_at          timestamptz,
  add column if not exists total_purchase_cost  numeric(14,2) not null default 0,
  add column if not exists total_logistics_cost numeric(14,2) not null default 0,
  add column if not exists total_other_cost     numeric(14,2) not null default 0,
  add column if not exists total_margin         numeric(14,2) not null default 0;

alter table public.quotations
  add constraint quotations_costs_chk
    check (total_purchase_cost >= 0 and total_logistics_cost >= 0 and total_other_cost >= 0),
  add constraint quotations_revision_not_self_chk
    check (revision_of is null or revision_of <> id);

comment on column public.quotations.payment_terms is 'Payment terms quoted to the customer (e.g. 30% advance, 70% on delivery).';
comment on column public.quotations.delivery_terms is 'Delivery terms quoted (weeks, ex-works/for site, etc.).';
comment on column public.quotations.warranty is 'Warranty offered on this quotation.';
comment on column public.quotations.revision_of is 'The quotation this row revises. A revision is a new row; the original is never overwritten.';
comment on column public.quotations.total_purchase_cost is 'Recalculated by trigger from the lines (sum of quantity x purchase cost).';
comment on column public.quotations.total_margin is 'Recalculated by trigger: net selling (ex-tax) minus total cost. May be negative.';

create index if not exists quotations_revision_idx on public.quotations (revision_of);

-- -----------------------------------------------------------------------------
-- 2. Quotation lines: OEM cost, logistics, other cost, technical compliance,
--    and generated cost / margin / margin% columns.
-- -----------------------------------------------------------------------------
alter table public.quotation_items
  add column if not exists purchase_unit_cost  numeric(14,2) not null default 0,
  add column if not exists logistics_unit_cost numeric(14,2) not null default 0,
  add column if not exists other_unit_cost     numeric(14,2) not null default 0,
  add column if not exists technical_compliance text not null default 'pending';

alter table public.quotation_items
  add constraint quotation_items_costs_chk
    check (purchase_unit_cost >= 0 and logistics_unit_cost >= 0 and other_unit_cost >= 0),
  add constraint quotation_items_tech_compliance_chk
    check (technical_compliance in ('pending','compliant','partially_compliant','non_compliant','not_applicable'));

alter table public.quotation_items
  add column if not exists line_base numeric(14,2) generated always as
    (round(quantity * unit_price * (1 - discount_pct / 100), 2)) stored,
  add column if not exists line_cost numeric(14,2) generated always as
    (round(quantity * (purchase_unit_cost + logistics_unit_cost + other_unit_cost), 2)) stored,
  add column if not exists line_margin numeric(14,2) generated always as
    (round(quantity * unit_price * (1 - discount_pct / 100), 2)
     - round(quantity * (purchase_unit_cost + logistics_unit_cost + other_unit_cost), 2)) stored,
  add column if not exists line_margin_pct numeric(8,2) generated always as
    (case
       when round(quantity * unit_price * (1 - discount_pct / 100), 2) > 0
       then round(
         (round(quantity * unit_price * (1 - discount_pct / 100), 2)
          - round(quantity * (purchase_unit_cost + logistics_unit_cost + other_unit_cost), 2))
         / round(quantity * unit_price * (1 - discount_pct / 100), 2) * 100, 2)
       else null
     end) stored;

comment on column public.quotation_items.purchase_unit_cost is 'Per-unit cost from the OEM.';
comment on column public.quotation_items.logistics_unit_cost is 'Per-unit logistics/freight cost.';
comment on column public.quotation_items.other_unit_cost is 'Per-unit other cost (packing, installation, etc.).';
comment on column public.quotation_items.unit_price is 'Per-unit SELLING price quoted to the customer.';
comment on column public.quotation_items.line_base is 'GENERATED: net selling before tax = round(qty*unit_price*(1-discount/100),2).';
comment on column public.quotation_items.line_cost is 'GENERATED: round(qty*(purchase+logistics+other),2).';
comment on column public.quotation_items.line_margin is 'GENERATED: line_base - line_cost.';
comment on column public.quotation_items.line_margin_pct is 'GENERATED: margin as a percentage of net selling.';
comment on column public.quotation_items.technical_compliance is
  'pending | compliant | partially_compliant | non_compliant | not_applicable.';

-- -----------------------------------------------------------------------------
-- 3. Header totals now include costs and margin (replaces the generic trigger).
-- -----------------------------------------------------------------------------
create or replace function app.recalc_quotation_totals()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  v_id := case when tg_op = 'DELETE' then old.quotation_id else new.quotation_id end;
  if v_id is null then return null; end if;

  update public.quotations q
     set subtotal             = coalesce(s.base, 0),
         tax_total            = coalesce(s.grand, 0) - coalesce(s.base, 0),
         grand_total          = coalesce(s.grand, 0),
         total_purchase_cost  = coalesce(s.pcost, 0),
         total_logistics_cost = coalesce(s.lcost, 0),
         total_other_cost     = coalesce(s.ocost, 0),
         total_margin         = coalesce(s.margin, 0),
         updated_at           = now()
    from (
      select sum(line_base)                              as base,
             sum(line_total)                             as grand,
             sum(round(quantity * purchase_unit_cost, 2)) as pcost,
             sum(round(quantity * logistics_unit_cost, 2)) as lcost,
             sum(round(quantity * other_unit_cost, 2))   as ocost,
             sum(line_margin)                            as margin
        from public.quotation_items
       where quotation_id = v_id
    ) s
   where q.id = v_id;

  return null;
end;
$$;

comment on function app.recalc_quotation_totals() is
  'Trigger function: recalculates quotation totals including cost and margin from its lines.';

drop trigger if exists trg_totals_quotation on public.quotation_items;
create trigger trg_totals_quotation
  after insert or update or delete on public.quotation_items
  for each row execute function app.recalc_quotation_totals();

-- -----------------------------------------------------------------------------
-- 4. One approved approval step per quotation (no double approval).
-- -----------------------------------------------------------------------------
create unique index if not exists quotation_approvals_one_approved_idx
  on public.quotation_approvals (quotation_id) where (decision = 'approved');

-- -----------------------------------------------------------------------------
-- 5. Immutability. An approved (or submitted/won/lost) quotation and its lines
--    can never be changed. The only permitted change on a frozen quotation is
--    its status (and approval metadata) ??? any content change must be a revision.
-- -----------------------------------------------------------------------------
create or replace function app.protect_approved_quotation()
returns trigger
language plpgsql
as $$
begin
  if old.status in ('approved','submitted','won','lost') then
    if new.customer_id            is distinct from old.customer_id
       or new.tender_id           is distinct from old.tender_id
       or new.opportunity_id      is distinct from old.opportunity_id
       or new.quotation_no        is distinct from old.quotation_no
       or new.version             is distinct from old.version
       or new.quote_date          is distinct from old.quote_date
       or new.validity_date       is distinct from old.validity_date
       or new.currency            is distinct from old.currency
       or new.subtotal            is distinct from old.subtotal
       or new.tax_total           is distinct from old.tax_total
       or new.grand_total         is distinct from old.grand_total
       or new.margin_pct          is distinct from old.margin_pct
       or new.payment_terms       is distinct from old.payment_terms
       or new.delivery_terms      is distinct from old.delivery_terms
       or new.warranty            is distinct from old.warranty
       or new.revision_of         is distinct from old.revision_of
       or new.notes               is distinct from old.notes
       or new.total_purchase_cost is distinct from old.total_purchase_cost
       or new.total_logistics_cost is distinct from old.total_logistics_cost
       or new.total_other_cost    is distinct from old.total_other_cost
       or new.total_margin        is distinct from old.total_margin
    then
      raise exception 'Quotation % v% is % and cannot be edited; create a revision instead',
        old.quotation_no, old.version, old.status
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

comment on function app.protect_approved_quotation() is
  'Trigger function: forbids content edits to an approved/submitted/won/lost quotation. Status changes are allowed.';

create trigger trg_protect_approved_quotation
  before update on public.quotations
  for each row execute function app.protect_approved_quotation();

create or replace function app.protect_approved_quotation_items()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id     uuid;
  v_status text;
  v_no     text;
  v_ver    integer;
begin
  v_id := case when tg_op = 'DELETE' then old.quotation_id else new.quotation_id end;
  select status, quotation_no, version
    into v_status, v_no, v_ver
    from public.quotations
   where id = v_id;

  if v_status in ('approved','submitted','won','lost') then
    raise exception 'Quotation % v% is % and its lines cannot be changed; create a revision instead',
      v_no, v_ver, v_status
      using errcode = 'check_violation';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

comment on function app.protect_approved_quotation_items() is
  'Trigger function: forbids line changes on an approved/submitted/won/lost quotation.';

create trigger trg_protect_quotation_items
  before insert or update or delete on public.quotation_items
  for each row execute function app.protect_approved_quotation_items();

-- -----------------------------------------------------------------------------
-- 6. Let the sales team read quotation-related activity history.
--    (Other audit rows stay restricted as before.)
-- -----------------------------------------------------------------------------
create policy audit_logs_quotation_activity on public.audit_logs for select to authenticated
  using (
    app.is_staff()
    and entity_table in ('quotations', 'quotation_items', 'quotation_approvals')
  );


-- ============================== 0016_procurement_module.sql ==============================
-- =============================================================================
-- 0016_procurement_module.sql
-- Procurement module support.
-- Chain: Customer Order -> Material Requirement -> Purchase Request -> OEM RFQ
--        -> OEM Quotation -> OEM Selection -> Purchase Approval -> Purchase Order
--        -> Expected Delivery -> Material Receipt -> PDI -> Ready for Dispatch
-- Adds: material_requirements(+items), oem_rfqs(+items), oem_quotations(+items),
--       purchase_approvals, procurement_documents, and the links/terms needed to
--       track OEM, product, qty, price, expected/actual delivery, payment terms,
--       warranty, compliance documents and status (with delivery-date triggers).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Material requirement (demand derived from a customer order)
-- -----------------------------------------------------------------------------
create table public.material_requirements (
  id                uuid primary key default gen_random_uuid(),
  requirement_no    text not null unique,
  customer_order_id uuid references public.customer_orders(id) on delete set null,
  requested_by      uuid references public.users(id),
  required_by_date  date,
  priority          text not null default 'medium',
  status            text not null default 'open',
  notes             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid default app.current_user_id(),
  updated_by        uuid default app.current_user_id(),
  constraint material_requirements_priority_chk check (priority in ('low','medium','high','critical')),
  constraint material_requirements_status_chk check (status in
    ('open','sourcing','rfq_sent','quoted','ordered','partially_received','received','cancelled'))
);

comment on table public.material_requirements is
  'Material requirement: the demand that must be procured to fulfil a customer order. First step of procurement.';
comment on column public.material_requirements.required_by_date is
  'The date the material must be available; used to flag OEM delivery risk against the customer order.';

create index material_requirements_order_idx on public.material_requirements (customer_order_id);
create index material_requirements_status_idx on public.material_requirements (status);

create table public.material_requirement_items (
  id                     uuid primary key default gen_random_uuid(),
  material_requirement_id uuid not null references public.material_requirements(id) on delete cascade,
  line_no                integer not null,
  product_id             uuid references public.products(id) on delete set null,
  order_item_id          uuid references public.order_items(id) on delete set null,
  description            text not null,
  quantity               numeric(14,3) not null,
  unit                   text not null default 'NO',
  required_by            date,
  status                 text not null default 'open',
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  created_by             uuid default app.current_user_id(),
  updated_by             uuid default app.current_user_id(),
  constraint material_requirement_items_unique unique (material_requirement_id, line_no),
  constraint material_requirement_items_qty_chk check (quantity > 0),
  constraint material_requirement_items_status_chk check (status in
    ('open','rfq_sent','quoted','ordered','received','cancelled')),
  constraint material_requirement_items_desc_not_blank check (btrim(description) <> '')
);

comment on table public.material_requirement_items is 'Line items of a material requirement.';
create index material_requirement_items_req_idx on public.material_requirement_items (material_requirement_id);

-- -----------------------------------------------------------------------------
-- 2. OEM RFQ (one row per OEM the RFQ is sent to)
-- -----------------------------------------------------------------------------
create table public.oem_rfqs (
  id                      uuid primary key default gen_random_uuid(),
  rfq_no                  text not null,
  oem_id                  uuid not null references public.oems(id) on delete restrict,
  material_requirement_id uuid references public.material_requirements(id) on delete set null,
  purchase_request_id     uuid references public.purchase_requests(id) on delete set null,
  sent_date               date,
  due_date                date,
  currency                text not null default 'INR',
  status                  text not null default 'draft',
  notes                   text,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  created_by              uuid default app.current_user_id(),
  updated_by              uuid default app.current_user_id(),
  constraint oem_rfqs_unique unique (rfq_no, oem_id),
  constraint oem_rfqs_status_chk check (status in ('draft','sent','quotes_received','closed','cancelled'))
);

comment on table public.oem_rfqs is
  'A request for quotation sent to one OEM. Several rows can share an rfq_no (one per supplier).';
create index oem_rfqs_oem_idx on public.oem_rfqs (oem_id);
create index oem_rfqs_requirement_idx on public.oem_rfqs (material_requirement_id);

create table public.oem_rfq_items (
  id                          uuid primary key default gen_random_uuid(),
  oem_rfq_id                  uuid not null references public.oem_rfqs(id) on delete cascade,
  line_no                     integer not null,
  product_id                  uuid references public.products(id) on delete set null,
  material_requirement_item_id uuid references public.material_requirement_items(id) on delete set null,
  description                 text not null,
  quantity                    numeric(14,3) not null,
  unit                        text not null default 'NO',
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  created_by                  uuid default app.current_user_id(),
  updated_by                  uuid default app.current_user_id(),
  constraint oem_rfq_items_unique unique (oem_rfq_id, line_no),
  constraint oem_rfq_items_qty_chk check (quantity > 0),
  constraint oem_rfq_items_desc_not_blank check (btrim(description) <> '')
);

comment on table public.oem_rfq_items is 'Line items asked of the OEM on an RFQ.';

-- -----------------------------------------------------------------------------
-- 3. OEM quotation (the OEM's priced reply)
-- -----------------------------------------------------------------------------
create table public.oem_quotations (
  id             uuid primary key default gen_random_uuid(),
  quotation_no   text not null unique,
  oem_id         uuid not null references public.oems(id) on delete restrict,
  oem_rfq_id     uuid references public.oem_rfqs(id) on delete set null,
  quote_date     date not null default current_date,
  validity_date  date,
  currency       text not null default 'INR',
  payment_terms  text,
  delivery_terms text,
  warranty       text,
  lead_time_days integer,
  subtotal       numeric(14,2) not null default 0,
  tax_total      numeric(14,2) not null default 0,
  grand_total    numeric(14,2) not null default 0,
  status         text not null default 'received',
  selected_at    timestamptz,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     uuid default app.current_user_id(),
  updated_by     uuid default app.current_user_id(),
  constraint oem_quotations_status_chk check (status in ('received','selected','rejected','expired')),
  constraint oem_quotations_lead_chk check (lead_time_days is null or lead_time_days >= 0),
  constraint oem_quotations_validity_chk check (validity_date is null or validity_date >= quote_date)
);

comment on table public.oem_quotations is
  'A priced quotation received from an OEM. Selecting one creates the purchase order.';
comment on column public.oem_quotations.lead_time_days is 'OEM-stated lead time; combined with the quote date gives the expected delivery.';
comment on column public.oem_quotations.status is 'received | selected | rejected | expired.';

create index oem_quotations_oem_idx on public.oem_quotations (oem_id);
create index oem_quotations_rfq_idx on public.oem_quotations (oem_rfq_id);

create table public.oem_quotation_items (
  id                  uuid primary key default gen_random_uuid(),
  oem_quotation_id    uuid not null references public.oem_quotations(id) on delete cascade,
  line_no             integer not null,
  oem_rfq_item_id     uuid references public.oem_rfq_items(id) on delete set null,
  product_id          uuid references public.products(id) on delete set null,
  description         text not null,
  quantity            numeric(14,3) not null,
  unit                text not null default 'NO',
  unit_price          numeric(14,2) not null default 0,
  discount_pct        numeric(6,2) not null default 0,
  tax_pct             numeric(6,2) not null default 0,
  line_total          numeric(14,2) generated always as
    (round(quantity * unit_price * (1 - discount_pct / 100) * (1 + tax_pct / 100), 2)) stored,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid default app.current_user_id(),
  updated_by          uuid default app.current_user_id(),
  constraint oem_quotation_items_unique unique (oem_quotation_id, line_no),
  constraint oem_quotation_items_qty_chk check (quantity > 0),
  constraint oem_quotation_items_price_chk check (unit_price >= 0),
  constraint oem_quotation_items_desc_not_blank check (btrim(description) <> '')
);

comment on table public.oem_quotation_items is 'Line items of an OEM quotation. line_total is generated.';
comment on column public.oem_quotation_items.unit_price is 'OEM per-unit purchase price.';

-- -----------------------------------------------------------------------------
-- 4. Purchase approval trail
-- -----------------------------------------------------------------------------
create table public.purchase_approvals (
  id                 uuid primary key default gen_random_uuid(),
  purchase_order_id  uuid not null references public.purchase_orders(id) on delete cascade,
  step_no            integer not null default 1,
  approver_user_id   uuid references public.users(id),
  decision           text not null default 'pending',
  comments           text,
  decided_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  created_by         uuid default app.current_user_id(),
  updated_by         uuid default app.current_user_id(),
  constraint purchase_approvals_unique unique (purchase_order_id, step_no),
  constraint purchase_approvals_decision_chk check (decision in ('pending','approved','rejected','returned'))
);

comment on table public.purchase_approvals is 'Approval steps for a purchase order.';
create index purchase_approvals_po_idx on public.purchase_approvals (purchase_order_id);
create unique index purchase_approvals_one_approved_idx
  on public.purchase_approvals (purchase_order_id) where (decision = 'approved');

-- -----------------------------------------------------------------------------
-- 5. Compliance / procurement documents (OEM certs, warranty, packing lists)
-- -----------------------------------------------------------------------------
create table public.procurement_documents (
  id          uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id   uuid not null,
  document_id uuid not null references public.documents(id) on delete cascade,
  doc_type    text not null default 'other',
  expires_on  date,
  notes       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid default app.current_user_id(),
  updated_by  uuid default app.current_user_id(),
  constraint procurement_documents_unique unique (entity_type, entity_id, document_id),
  constraint procurement_documents_entity_chk check (entity_type in
    ('oem','oem_quotation','purchase_order','material_receipt')),
  constraint procurement_documents_type_chk check (doc_type in
    ('compliance_certificate','test_certificate','iso_certificate','gst_certificate','pan',
     'warranty_certificate','packing_list','invoice','other'))
);

comment on table public.procurement_documents is
  'Links a stored document to a procurement entity as a compliance/quality document, with an optional expiry for alerts.';
create index procurement_documents_entity_idx on public.procurement_documents (entity_type, entity_id);

-- -----------------------------------------------------------------------------
-- 6. Links and terms on existing tables
-- -----------------------------------------------------------------------------
alter table public.purchase_requests
  add column if not exists material_requirement_id uuid references public.material_requirements(id) on delete set null;

alter table public.purchase_orders
  add column if not exists oem_quotation_id        uuid references public.oem_quotations(id) on delete set null,
  add column if not exists material_requirement_id uuid references public.material_requirements(id) on delete set null,
  add column if not exists payment_terms           text,
  add column if not exists warranty                text,
  add column if not exists actual_delivery_date    date;

comment on column public.purchase_orders.actual_delivery_date is
  'Maintained by trigger from the material receipts linked to this purchase order.';

-- -----------------------------------------------------------------------------
-- 7. Trigger: keep purchase_orders.actual_delivery_date true to its receipts
-- -----------------------------------------------------------------------------
create or replace function app.recalc_po_actual_delivery()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_po uuid;
begin
  v_po := coalesce(new.purchase_order_id, old.purchase_order_id);
  if v_po is null then return null; end if;

  update public.purchase_orders po
     set actual_delivery_date = (
           select max(r.received_date)
             from public.material_receipts r
            where r.purchase_order_id = v_po
              and r.status in ('received','partial')
         ),
         updated_at = now()
   where po.id = v_po;

  return null;
end;
$$;

comment on function app.recalc_po_actual_delivery() is
  'Trigger function: sets purchase_orders.actual_delivery_date to the latest receipt date.';

create trigger trg_po_actual_delivery
  after insert or update or delete on public.material_receipts
  for each row execute function app.recalc_po_actual_delivery();

-- -----------------------------------------------------------------------------
-- 8. Totals for OEM quotations (reuses the generic parent-totals function)
-- -----------------------------------------------------------------------------
create trigger trg_totals_oem_quotation
  after insert or update or delete on public.oem_quotation_items
  for each row execute function app.recalc_parent_totals('oem_quotations', 'oem_quotation_id');

-- -----------------------------------------------------------------------------
-- 9. RLS for the new tables
-- -----------------------------------------------------------------------------
alter table public.material_requirements      enable row level security;
alter table public.material_requirement_items enable row level security;
alter table public.oem_rfqs                   enable row level security;
alter table public.oem_rfq_items              enable row level security;
alter table public.oem_quotations             enable row level security;
alter table public.oem_quotation_items        enable row level security;
alter table public.purchase_approvals         enable row level security;
alter table public.procurement_documents      enable row level security;

grant select, insert, update, delete on
  public.material_requirements, public.material_requirement_items,
  public.oem_rfqs, public.oem_rfq_items,
  public.oem_quotations, public.oem_quotation_items,
  public.purchase_approvals, public.procurement_documents
to authenticated;

-- read: all staff
create policy material_requirements_select on public.material_requirements for select to authenticated using (app.is_staff());
create policy material_requirement_items_select on public.material_requirement_items for select to authenticated using (app.is_staff());
create policy oem_rfqs_select on public.oem_rfqs for select to authenticated using (app.is_staff());
create policy oem_rfq_items_select on public.oem_rfq_items for select to authenticated using (app.is_staff());
create policy oem_quotations_select on public.oem_quotations for select to authenticated using (app.is_staff());
create policy oem_quotation_items_select on public.oem_quotation_items for select to authenticated using (app.is_staff());
create policy purchase_approvals_select on public.purchase_approvals for select to authenticated using (app.is_staff());
create policy procurement_documents_select on public.procurement_documents for select to authenticated using (app.is_staff());

-- write: sourcing by sales/procurement
create policy material_requirements_insert on public.material_requirements for insert to authenticated with check (app.has_any_role(array['admin','procurement','sales']));
create policy material_requirements_update on public.material_requirements for update to authenticated using (app.has_any_role(array['admin','procurement','sales'])) with check (app.has_any_role(array['admin','procurement','sales']));
create policy material_requirements_delete on public.material_requirements for delete to authenticated using (app.is_admin());
create policy material_requirement_items_insert on public.material_requirement_items for insert to authenticated with check (app.has_any_role(array['admin','procurement','sales']));
create policy material_requirement_items_update on public.material_requirement_items for update to authenticated using (app.has_any_role(array['admin','procurement','sales'])) with check (app.has_any_role(array['admin','procurement','sales']));
create policy material_requirement_items_delete on public.material_requirement_items for delete to authenticated using (app.is_admin());

create policy oem_rfqs_insert on public.oem_rfqs for insert to authenticated with check (app.has_any_role(array['admin','procurement']));
create policy oem_rfqs_update on public.oem_rfqs for update to authenticated using (app.has_any_role(array['admin','procurement'])) with check (app.has_any_role(array['admin','procurement']));
create policy oem_rfqs_delete on public.oem_rfqs for delete to authenticated using (app.is_admin());
create policy oem_rfq_items_insert on public.oem_rfq_items for insert to authenticated with check (app.has_any_role(array['admin','procurement']));
create policy oem_rfq_items_update on public.oem_rfq_items for update to authenticated using (app.has_any_role(array['admin','procurement'])) with check (app.has_any_role(array['admin','procurement']));
create policy oem_rfq_items_delete on public.oem_rfq_items for delete to authenticated using (app.is_admin());

create policy oem_quotations_insert on public.oem_quotations for insert to authenticated with check (app.has_any_role(array['admin','procurement']));
create policy oem_quotations_update on public.oem_quotations for update to authenticated using (app.has_any_role(array['admin','procurement'])) with check (app.has_any_role(array['admin','procurement']));
create policy oem_quotations_delete on public.oem_quotations for delete to authenticated using (app.is_admin());
create policy oem_quotation_items_insert on public.oem_quotation_items for insert to authenticated with check (app.has_any_role(array['admin','procurement']));
create policy oem_quotation_items_update on public.oem_quotation_items for update to authenticated using (app.has_any_role(array['admin','procurement'])) with check (app.has_any_role(array['admin','procurement']));
create policy oem_quotation_items_delete on public.oem_quotation_items for delete to authenticated using (app.is_admin());

-- purchase approval is a management/admin action
create policy purchase_approvals_insert on public.purchase_approvals for insert to authenticated with check (app.has_any_role(array['admin','management']));
create policy purchase_approvals_update on public.purchase_approvals for update to authenticated using (app.has_any_role(array['admin','management'])) with check (app.has_any_role(array['admin','management']));
create policy purchase_approvals_delete on public.purchase_approvals for delete to authenticated using (app.is_admin());

create policy procurement_documents_insert on public.procurement_documents for insert to authenticated with check (app.has_any_role(array['admin','procurement','qa','stores']));
create policy procurement_documents_update on public.procurement_documents for update to authenticated using (app.has_any_role(array['admin','procurement','qa','stores'])) with check (app.has_any_role(array['admin','procurement','qa','stores']));
create policy procurement_documents_delete on public.procurement_documents for delete to authenticated using (app.is_admin());

-- -----------------------------------------------------------------------------
-- 10. Procurement activity readable by staff (for activity history)
-- -----------------------------------------------------------------------------
create policy audit_logs_procurement_activity on public.audit_logs for select to authenticated
  using (
    app.is_staff()
    and entity_table in (
      'material_requirements','material_requirement_items',
      'oem_rfqs','oem_rfq_items','oem_quotations','oem_quotation_items',
      'purchase_requests','purchase_request_items',
      'purchase_orders','purchase_order_items',
      'purchase_approvals','procurement_documents',
      'material_receipts','material_receipt_items','pdi_records','pdi_items'
    )
  );

-- -----------------------------------------------------------------------------
-- 11. Standard updated_at + audit triggers for the new tables
-- -----------------------------------------------------------------------------
do $$
declare
  r record;
  new_tables text[] := array[
    'material_requirements','material_requirement_items',
    'oem_rfqs','oem_rfq_items','oem_quotations','oem_quotation_items',
    'purchase_approvals','procurement_documents'
  ];
begin
  for r in
    select c.table_name
      from information_schema.columns c
     where c.table_schema = 'public'
       and c.column_name = 'updated_at'
       and c.table_name = any (new_tables)
  loop
    execute format('drop trigger if exists %I on public.%I', 'trg_touch_' || r.table_name, r.table_name);
    execute format('create trigger %I before update on public.%I for each row execute function app.set_updated_at()',
                   'trg_touch_' || r.table_name, r.table_name);
  end loop;

  for r in
    select unnest(new_tables) as table_name
  loop
    execute format('drop trigger if exists %I on public.%I', 'trg_audit_' || r.table_name, r.table_name);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.audit_row()',
                   'trg_audit_' || r.table_name, r.table_name);
  end loop;
end $$;

-- ============================== seed/0001_roles.sql ==============================
-- =============================================================================
-- seed/0001_seed.sql
-- Baseline reference data. Safe to re-run (idempotent).
-- =============================================================================

-- The ten roles used by all RLS policies. Keep these codes in sync with
-- app.is_staff() in 0003_security_helpers.sql.
insert into public.roles (code, name, description) values
  ('admin',       'Administrator',            'Full access: users, roles, settings and all data.'),
  ('management',  'Management / Director',    'Read all; approve quotations and purchase orders.'),
  ('sales',       'Sales / Tender Executive', 'Tenders, opportunities, quotations, customer orders.'),
  ('technical',   'Technical / Engineering',  'Technical requirements, feasibility, product specifications.'),
  ('procurement', 'Procurement Officer',      'OEM contacts, RFQs, purchase orders, supplier prices.'),
  ('stores',      'Stores / Receiving',       'Goods receipt against purchase orders.'),
  ('qa',          'QA / Inspection',          'PDI and inspection records, certificates, compliance.'),
  ('logistics',   'Logistics / Dispatch',     'Dispatches, delivery documents, proof of delivery.'),
  ('accounts',    'Accounts / Finance',       'Invoices, payments, receivables ageing.'),
  ('viewer',      'Viewer / Guest',           'Read-only access to business data.')
on conflict (code) do update
  set name = excluded.name,
      description = excluded.description,
      updated_at = now();

