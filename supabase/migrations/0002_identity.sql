-- =============================================================================
-- 0002_identity.sql
-- Identity and access: users, roles, user_roles.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- users
-- Our own user record. id is OUR identifier (referenced by every audit column),
-- auth_user_id mirrors the Supabase auth.users id. Keeping our own id is a
-- deliberate lock-in mitigation: history survives a change of auth provider.
-- -----------------------------------------------------------------------------
create table public.users (
  id            uuid primary key default gen_random_uuid(),
  auth_user_id  uuid unique,
  full_name     text not null,
  email         text not null unique,
  phone         text,
  designation   text,
  department    text,
  is_active     boolean not null default true,
  mfa_enabled   boolean not null default false,
  last_login_at timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid,
  updated_by    uuid,
  constraint users_email_lower_chk check (email = lower(email)),
  constraint users_full_name_not_blank check (btrim(full_name) <> '')
);

comment on table public.users is
  'Application users (staff). One row per person. id is our own identifier used by all audit columns; auth_user_id links to Supabase auth.users.';
comment on column public.users.auth_user_id is 'Supabase auth.users.id. Null until the user accepts an invite / signs up.';
comment on column public.users.is_active is 'Inactive users cannot sign in and RLS treats them as unauthenticated.';
comment on column public.users.created_by is 'User who created this row (FK users.id).';
comment on column public.users.updated_by is 'User who last updated this row (FK users.id).';

create index users_active_idx on public.users (is_active);
create index users_auth_user_idx on public.users (auth_user_id);

-- -----------------------------------------------------------------------------
-- roles
-- The role catalogue. code is the stable key used in user_roles and RLS.
-- -----------------------------------------------------------------------------
create table public.roles (
  code        text primary key,
  name        text not null,
  description text,
  is_system   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint roles_code_chk check (code ~ '^[a-z][a-z0-9_]*$')
);

comment on table public.roles is
  'Role catalogue. code is the stable key referenced by user_roles and used by all RLS policies.';
comment on column public.roles.is_system is 'True for the seeded roles that must not be deleted.';

-- -----------------------------------------------------------------------------
-- user_roles
-- Many-to-many between users and roles. Effective permissions are the union of
-- the active roles, except where segregation-of-duties triggers forbid.
-- -----------------------------------------------------------------------------
create table public.user_roles (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.users(id) on delete cascade,
  role_code  text not null references public.roles(code) on delete restrict,
  granted_at timestamptz not null default now(),
  granted_by uuid references public.users(id),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid,
  constraint user_roles_unique unique (user_id, role_code)
);

comment on table public.user_roles is
  'Grants a role to a user. A user may hold several roles; permissions are the union of active roles.';

create index user_roles_user_idx on public.user_roles (user_id);
create index user_roles_role_idx on public.user_roles (role_code);
