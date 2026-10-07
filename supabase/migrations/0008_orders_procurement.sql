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
