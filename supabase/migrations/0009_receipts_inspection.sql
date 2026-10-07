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
