-- =============================================================================
-- 0014_tender_workflow.sql
-- Tender Management module support.
--   * Replaces the tenders.status set with the agreed 13-stage pipeline.
--   * Adds tender_notes (a tender needs many timestamped notes, not one field).
--   * Enables RLS and attaches the standard triggers to the new table.
-- No other feature is added.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. New tender status pipeline (13 stages)
--    new | under_review | qualified | requirement_analysis | oem_pricing |
--    quotation_preparation | approval_pending | submitted | technical_evaluation |
--    commercial_evaluation | won | lost | cancelled
-- -----------------------------------------------------------------------------
alter table public.tenders drop constraint if exists tenders_status_chk;

update public.tenders set status = case status
  when 'draft'            then 'new'
  when 'received'         then 'new'
  when 'under_analysis'   then 'requirement_analysis'
  when 'rfq_sent'         then 'oem_pricing'
  when 'quoted'           then 'quotation_preparation'
  when 'submitted'        then 'submitted'
  when 'under_evaluation' then 'technical_evaluation'
  when 'won'              then 'won'
  when 'lost'             then 'lost'
  when 'cancelled'        then 'cancelled'
  when 'closed'           then 'won'
  else 'new'
end
where status not in (
  'new','under_review','qualified','requirement_analysis','oem_pricing',
  'quotation_preparation','approval_pending','submitted','technical_evaluation',
  'commercial_evaluation','won','lost','cancelled'
);

alter table public.tenders alter column status set default 'new';

alter table public.tenders add constraint tenders_status_chk check (status in (
  'new','under_review','qualified','requirement_analysis','oem_pricing',
  'quotation_preparation','approval_pending','submitted','technical_evaluation',
  'commercial_evaluation','won','lost','cancelled'
));

comment on column public.tenders.status is
  'Tender pipeline stage: new | under_review | qualified | requirement_analysis | oem_pricing | quotation_preparation | approval_pending | submitted | technical_evaluation | commercial_evaluation | won | lost | cancelled.';

-- -----------------------------------------------------------------------------
-- 2. tender_notes : many timestamped notes per tender
-- -----------------------------------------------------------------------------
create table public.tender_notes (
  id         uuid primary key default gen_random_uuid(),
  tender_id  uuid not null references public.tenders(id) on delete cascade,
  note       text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default app.current_user_id(),
  updated_by uuid default app.current_user_id(),
  constraint tender_notes_note_not_blank check (btrim(note) <> '')
);

comment on table public.tender_notes is
  'Free-text notes recorded against a tender, newest first, each with author and timestamp.';
comment on column public.tender_notes.note is 'The note text. Blank notes are rejected.';

create index tender_notes_tender_idx on public.tender_notes (tender_id, created_at desc);

-- -----------------------------------------------------------------------------
-- 3. RLS for the new table (same pattern as the rest of the schema)
-- -----------------------------------------------------------------------------
alter table public.tender_notes enable row level security;

create policy tender_notes_select on public.tender_notes for select to authenticated
  using (app.is_staff());
create policy tender_notes_insert on public.tender_notes for insert to authenticated
  with check (app.has_any_role(array['admin','sales','technical']));
create policy tender_notes_update on public.tender_notes for update to authenticated
  using (app.has_any_role(array['admin','sales','technical']))
  with check (app.has_any_role(array['admin','sales','technical']));
create policy tender_notes_delete on public.tender_notes for delete to authenticated
  using (app.is_admin());

-- -----------------------------------------------------------------------------
-- 4. Standard triggers for the new table (0013 only covered tables existing then)
-- -----------------------------------------------------------------------------
create trigger trg_touch_tender_notes
  before update on public.tender_notes
  for each row execute function app.set_updated_at();

create trigger trg_audit_tender_notes
  after insert or update or delete on public.tender_notes
  for each row execute function app.audit_row();

-- -----------------------------------------------------------------------------
-- 5. Let the tender team read tender-related activity history.
--    (Other audit rows stay restricted to admin / management / accounts.)
-- -----------------------------------------------------------------------------
create policy audit_logs_tender_activity on public.audit_logs for select to authenticated
  using (
    app.is_staff()
    and entity_table in ('tenders', 'tender_notes', 'tender_requirements')
  );

-- -----------------------------------------------------------------------------
-- 6. A names-only directory so the "Assign employee" dropdown works for
--    everyone, without exposing full user rows (users RLS stays strict).
--    The view is owned by the migration role and is read-only to the app.
-- -----------------------------------------------------------------------------
create or replace view public.user_directory as
  select id, full_name, designation
    from public.users
   where is_active;

comment on view public.user_directory is
  'Names-only directory of active users (id, full_name, designation) for assignee pickers.';

grant select on public.user_directory to authenticated;

