-- =============================================================================
-- 0003_security_helpers.sql
-- Security helper functions used by RLS policies and column defaults.
-- All are SECURITY DEFINER so they can read users/user_roles regardless of the
-- caller's own RLS, and STABLE so they are evaluated once per statement.
-- =============================================================================

-- The authenticated subject from the JWT (Supabase sets request.jwt.claims).
create or replace function app.jwt_sub()
returns uuid
language sql
stable
set search_path = pg_temp
as $$
  select (
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid;
$$;

comment on function app.jwt_sub() is
  'Returns the JWT subject (auth user id) as uuid, or NULL when unauthenticated.';

-- Our internal users.id for the signed-in subject. Matches on auth_user_id, or
-- on id as a fallback so the schema also works if ids are aligned.
create or replace function app.current_user_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select u.id
    from public.users u
   where u.is_active
     and (u.auth_user_id = app.jwt_sub() or u.id = app.jwt_sub())
   limit 1;
$$;

comment on function app.current_user_id() is
  'Returns the internal public.users.id of the signed-in user, or NULL if not authenticated/active.';

-- Active role codes held by the signed-in user.
create or replace function app.current_roles()
returns text[]
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(array_agg(ur.role_code order by ur.role_code), array[]::text[])
    from public.user_roles ur
   where ur.user_id = app.current_user_id()
     and (ur.expires_at is null or ur.expires_at > now());
$$;

comment on function app.current_roles() is
  'Returns the array of active role codes for the signed-in user.';

create or replace function app.has_role(p_role text)
returns boolean
language sql
stable
as $$
  select p_role = any (app.current_roles());
$$;

comment on function app.has_role(text) is 'True when the signed-in user holds the given role.';

create or replace function app.has_any_role(p_roles text[])
returns boolean
language sql
stable
as $$
  select app.current_roles() && p_roles;
$$;

comment on function app.has_any_role(text[]) is 'True when the signed-in user holds at least one of the given roles.';

create or replace function app.is_admin()
returns boolean
language sql
stable
as $$
  select app.has_role('admin');
$$;

comment on function app.is_admin() is 'True when the signed-in user holds the admin role.';

-- Any recognised, active role = a staff member allowed to read the business data.
create or replace function app.is_staff()
returns boolean
language sql
stable
as $$
  select app.has_any_role(array[
    'admin','management','sales','technical','procurement',
    'stores','qa','logistics','accounts','viewer'
  ]);
$$;

comment on function app.is_staff() is
  'True when the signed-in user holds any of the ten defined staff roles (i.e. is an authorised reader).';

create or replace function app.is_authenticated()
returns boolean
language sql
stable
as $$
  select app.current_user_id() is not null;
$$;

comment on function app.is_authenticated() is
  'True when the request maps to an active application user.';

-- Convenience grants: RLS policy expressions call these functions, so the
-- authenticated role needs EXECUTE on them.
grant usage on schema app to authenticated;
grant execute on all functions in schema app to authenticated;
