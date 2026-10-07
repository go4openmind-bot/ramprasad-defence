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
