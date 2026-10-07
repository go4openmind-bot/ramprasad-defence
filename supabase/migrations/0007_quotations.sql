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
