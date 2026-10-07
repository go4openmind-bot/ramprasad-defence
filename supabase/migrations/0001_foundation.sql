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
