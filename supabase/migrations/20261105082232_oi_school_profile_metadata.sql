begin;

-- Evidence-flow academic metadata is visible only through an authenticated
-- RPC and remains separate from deliberately entered public donor information.
create table benchmark_private.oi_school_profile_metadata (
  account_id uuid primary key references public.oi_profiles(id) on delete cascade,
  school_id text not null references public.oi_schools(id),
  admission_year integer check (admission_year between 1900 and 9999),
  department text check (department is null or (
    department = btrim(department, E' \t\n\r\f\013') and length(department) between 1 and 100
  )),
  updated_at timestamptz not null default now()
);
alter table benchmark_private.oi_school_profile_metadata enable row level security;
revoke all on benchmark_private.oi_school_profile_metadata from public, anon, authenticated;

create function benchmark_private.oi_read_school_profile() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := benchmark_private.oi_actor();
  result jsonb;
begin
  select to_jsonb(profile) || jsonb_build_object(
    'school_admission_year', metadata.admission_year, 'school_department', metadata.department
  ) into result
  from public.oi_profiles profile
  left join benchmark_private.oi_school_profile_metadata metadata
    on metadata.account_id = profile.id and metadata.school_id = profile.school_id
  where profile.id = actor;
  if result is null then raise exception 'school_profile_unavailable' using errcode = 'PT404'; end if;
  return result;
end;
$$;
revoke all on function benchmark_private.oi_read_school_profile() from public, anon, authenticated;
grant execute on function benchmark_private.oi_read_school_profile() to authenticated;

create function public.oi_school_profile() returns jsonb
language sql security invoker set search_path = '' as $$
  select benchmark_private.oi_read_school_profile();
$$;
revoke all on function public.oi_school_profile() from public, anon, authenticated;
grant execute on function public.oi_school_profile() to authenticated;

create function benchmark_private.oi_update_school_profile(
  p_school_id text, p_admission_year integer, p_department text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := benchmark_private.oi_actor();
  cleaned_department text := btrim(p_department, E' \t\n\r\f\013');
  current_year integer := extract(year from timezone('UTC', now()))::integer;
begin
  if p_school_id is null or not exists (select 1 from public.oi_schools where id = p_school_id)
    or p_admission_year is null or p_admission_year not between 1900 and current_year
    or (p_department is not null and (length(cleaned_department) not between 1 and 100)) then
    raise exception 'invalid_school_profile' using errcode = '22023';
  end if;

  -- Lock membership before the profile, matching account merge's lock order.
  -- Legacy nickname/school-only PATCHes never touch the private metadata.
  update public.oi_profiles set school_id = p_school_id, updated_at = now() where id = actor;
  if not found then raise exception 'school_profile_unavailable' using errcode = 'PT404'; end if;
  insert into benchmark_private.oi_school_profile_metadata (account_id, school_id, admission_year, department)
  values (actor, p_school_id, p_admission_year, cleaned_department)
  on conflict (account_id) do update
    set school_id = excluded.school_id, admission_year = excluded.admission_year,
        department = excluded.department, updated_at = now();
  return benchmark_private.oi_read_school_profile();
end;
$$;
revoke all on function benchmark_private.oi_update_school_profile(text, integer, text) from public, anon, authenticated;
grant execute on function benchmark_private.oi_update_school_profile(text, integer, text) to authenticated;

create function public.oi_update_school_profile(p_school_id text, p_admission_year integer, p_department text) returns jsonb
language sql security invoker set search_path = '' as $$
  select benchmark_private.oi_update_school_profile(p_school_id, p_admission_year, p_department);
$$;
revoke all on function public.oi_update_school_profile(text, integer, text) from public, anon, authenticated;
grant execute on function public.oi_update_school_profile(text, integer, text) to authenticated;

-- Fail atomically if another deployment changed the capability contract.
do $$ begin
  if (select md5(btrim(prosrc, E' \n\r\t')) from pg_proc where oid = 'public.oi_capabilities()'::regprocedure)
    not in ('2a0ecd9d487aa12cd16834e56db7065e', '495eb677ead4cfee7641871d7022e76c') then
    raise exception 'oi_capabilities drift requires review before adding school profile metadata';
  end if;
end; $$;
do $patch$
declare definition text;
begin
  if to_regprocedure('benchmark_private.oi_unapproved_drafts_enabled()') is not null then
    definition := $definition$create or replace function public.oi_capabilities() returns jsonb
language sql security invoker set search_path = '' as $$
  with context as (select benchmark_private.oi_account_context() value)
  select jsonb_build_object('operator', benchmark_private.oi_is_operator(), 'coins_enabled', false,
    'unapproved_drafts_enabled', benchmark_private.oi_unapproved_drafts_enabled(),
    'account_merge_enabled', true, 'account_id', value -> 'id', 'account_member_ids', value -> 'member_ids',
    'account_providers', value -> 'account_providers', 'school_profile_enabled', true) from context;
$$;
$definition$;
  else
    definition := $definition$create or replace function public.oi_capabilities() returns jsonb
language sql security invoker set search_path = '' as $$
  with context as (select benchmark_private.oi_account_context() value)
  select jsonb_build_object('operator', benchmark_private.oi_is_operator(), 'coins_enabled', false,
    'account_merge_enabled', true, 'account_id', value -> 'id', 'account_member_ids', value -> 'member_ids',
    'account_providers', value -> 'account_providers', 'school_profile_enabled', true) from context;
$$;
$definition$;
  end if;
  execute definition;
end; $patch$;
revoke all on function public.oi_capabilities() from public, anon;
grant execute on function public.oi_capabilities() to authenticated;

commit;
