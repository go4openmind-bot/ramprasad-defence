-- =============================================================================
-- 0015_quotation_module.sql
-- Quotation Management module support.
--   * Cost, logistics, other cost, margin and selling price at line and header.
--   * Commercial terms on the quotation (payment, delivery, warranty, validity).
--   * Technical compliance per line.
--   * Revisions (revision_of) — an approved quotation is never overwritten.
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
--    its status (and approval metadata) — any content change must be a revision.
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

