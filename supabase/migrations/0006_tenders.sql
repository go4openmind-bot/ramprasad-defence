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
