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
