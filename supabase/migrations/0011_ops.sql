-- =============================================================================
-- 0011_ops.sql
-- Operational tables: tasks, notifications and the append-only audit log.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- tasks : follow-ups / to-dos, optionally linked to any business record
-- -----------------------------------------------------------------------------
create table public.tasks (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  description  text,
  entity_table text,
  entity_id    uuid,
  assigned_to  uuid references public.users(id) on delete set null,
  due_date     date,
  priority     text not null default 'medium',
  status       text not null default 'open',
  completed_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid,
  updated_by   uuid,
  constraint tasks_status_chk check (status in ('open','in_progress','blocked','done','cancelled')),
  constraint tasks_priority_chk check (priority in ('low','medium','high','critical')),
  constraint tasks_title_not_blank check (btrim(title) <> '')
);

comment on table public.tasks is
  'Follow-up tasks. Optionally linked to any business record via entity_table/entity_id; assigned to a user with a due date.';

create index tasks_assignee_idx on public.tasks (assigned_to);
create index tasks_status_idx on public.tasks (status);
create index tasks_due_idx on public.tasks (due_date);
create index tasks_entity_idx on public.tasks (entity_table, entity_id);

-- -----------------------------------------------------------------------------
-- notifications : in-app / email notifications per user
-- -----------------------------------------------------------------------------
create table public.notifications (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.users(id) on delete cascade,
  title        text not null,
  body         text,
  entity_table text,
  entity_id    uuid,
  channel      text not null default 'in_app',
  status       text not null default 'unread',
  read_at      timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid,
  updated_by   uuid,
  constraint notifications_channel_chk check (channel in ('in_app','email')),
  constraint notifications_status_chk check (status in ('unread','read','archived')),
  constraint notifications_title_not_blank check (btrim(title) <> '')
);

comment on table public.notifications is
  'Notifications delivered to a user (in-app or email), optionally linked to the record that caused them.';
comment on column public.notifications.status is 'unread | read | archived.';

create index notifications_user_idx on public.notifications (user_id, status);
create index notifications_created_idx on public.notifications (created_at desc);

-- -----------------------------------------------------------------------------
-- audit_logs : append-only change history. No updated_at by design.
-- Written by app.audit_row() (SECURITY DEFINER). No INSERT/UPDATE/DELETE policy
-- is granted to normal roles.
-- -----------------------------------------------------------------------------
create table public.audit_logs (
  id            uuid primary key default gen_random_uuid(),
  actor_user_id uuid references public.users(id) on delete set null,
  action        text not null,
  entity_table  text not null,
  entity_id     uuid,
  before_data   jsonb,
  after_data    jsonb,
  ip_address    inet,
  created_at    timestamptz not null default now(),
  constraint audit_logs_action_chk check (action in
    ('insert','update','delete','approve','submit','receive','dispatch','login','export','other'))
);

comment on table public.audit_logs is
  'Append-only audit trail: who changed what, when, and the before/after values. Written only by trigger.';
comment on column public.audit_logs.before_data is 'Row image before the change (null on insert).';
comment on column public.audit_logs.after_data is 'Row image after the change (null on delete).';

create index audit_logs_entity_idx on public.audit_logs (entity_table, entity_id, created_at desc);
create index audit_logs_actor_idx on public.audit_logs (actor_user_id, created_at desc);
create index audit_logs_created_idx on public.audit_logs (created_at desc);
