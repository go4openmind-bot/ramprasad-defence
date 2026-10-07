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
