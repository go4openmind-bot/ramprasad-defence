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
