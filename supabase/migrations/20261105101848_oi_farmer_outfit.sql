begin;

create function benchmark_private.oi_valid_farmer_outfit(value jsonb) returns boolean
language plpgsql immutable security invoker set search_path = '' as $$
begin
  if value is null or jsonb_typeof(value) <> 'object' or octet_length(value::text) > 4096 then return false; end if;
  if exists(select 1 from jsonb_object_keys(value) key where key not in ('version', 'character', 'slots'))
    or value -> 'version' is distinct from '1'::jsonb
    or jsonb_typeof(value -> 'character') is distinct from 'string'
    or value ->> 'character' not in ('kyu', 'cumber')
    or jsonb_typeof(value -> 'slots') is distinct from 'object' then return false; end if;
  if (select count(*) from jsonb_object_keys(value -> 'slots')) > 6 then return false; end if;
  return not exists(select 1 from jsonb_each(value -> 'slots') slot
    where slot.key not in ('top', 'bottom', 'shoes', 'hat', 'accessory', 'set')
      or jsonb_typeof(slot.value) <> 'string'
      or (slot.value #>> '{}') !~ '^[a-z0-9][a-z0-9-]{0,79}$');
end;
$$;
revoke all on function benchmark_private.oi_valid_farmer_outfit(jsonb) from public, anon, authenticated;

-- Only the canonical account's own client may access its outfit. This data is
-- independent of public story author profiles and other users' character art.
create table benchmark_private.oi_farmer_outfits (
  account_id uuid primary key references public.oi_profiles(id) on delete cascade,
  outfit jsonb not null check (benchmark_private.oi_valid_farmer_outfit(outfit)),
  updated_at timestamptz not null default now()
);
alter table benchmark_private.oi_farmer_outfits enable row level security;
revoke all on benchmark_private.oi_farmer_outfits from public, anon, authenticated;

create function benchmark_private.oi_read_farmer_outfit() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor uuid := benchmark_private.oi_actor();
begin
  return jsonb_build_object('account_id', actor, 'outfit',
    (select outfit from benchmark_private.oi_farmer_outfits where account_id = actor));
end;
$$;
revoke all on function benchmark_private.oi_read_farmer_outfit() from public, anon, authenticated;
grant execute on function benchmark_private.oi_read_farmer_outfit() to authenticated;
create function public.oi_farmer_outfit() returns jsonb
language sql security invoker set search_path = '' as $$
  select benchmark_private.oi_read_farmer_outfit();
$$;
revoke all on function public.oi_farmer_outfit() from public, anon, authenticated;
grant execute on function public.oi_farmer_outfit() to authenticated;

create function benchmark_private.oi_save_farmer_outfit(p_outfit jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor uuid := benchmark_private.oi_actor();
begin
  if not benchmark_private.oi_valid_farmer_outfit(p_outfit) then
    raise exception 'invalid_farmer_outfit' using errcode = '22023';
  end if;
  insert into benchmark_private.oi_farmer_outfits(account_id, outfit) values(actor, p_outfit)
  on conflict(account_id) do update set outfit = excluded.outfit, updated_at = now();
  return benchmark_private.oi_read_farmer_outfit();
end;
$$;
revoke all on function benchmark_private.oi_save_farmer_outfit(jsonb) from public, anon, authenticated;
grant execute on function benchmark_private.oi_save_farmer_outfit(jsonb) to authenticated;
create function public.oi_save_farmer_outfit(p_outfit jsonb) returns jsonb
language sql security invoker set search_path = '' as $$
  select benchmark_private.oi_save_farmer_outfit(p_outfit);
$$;
revoke all on function public.oi_save_farmer_outfit(jsonb) from public, anon, authenticated;
grant execute on function public.oi_save_farmer_outfit(jsonb) to authenticated;

-- Preserve all existing capability and merge fields; stop on unknown drift.
do $patch$
declare source text; definition text; anchor text;
begin
  select prosrc, pg_get_functiondef(oid) into source, definition from pg_proc
    where oid = 'public.oi_capabilities()'::regprocedure;
  anchor := '''school_profile_enabled'', true';
  if md5(btrim(source, E' \n\r\t')) not in ('289a2b7a3b77d5e0a7534d15979cea58', '4016b72e32c79a15e501932f96f6023e')
    or (length(definition) - length(replace(definition, anchor, ''))) / length(anchor) <> 1 then
    raise exception 'oi_capabilities drift requires review before adding farmer outfits';
  end if;
  execute replace(definition, anchor, anchor || ', ''farmer_outfit_enabled'', true');

  select prosrc, pg_get_functiondef(oid) into source, definition from pg_proc
    where oid = 'public.oi_merge_accounts(text,uuid,uuid,uuid,uuid,uuid,uuid,boolean)'::regprocedure;
  anchor := 'and not exists(select 1 from public.oi_stories where user_id=source_account)';
  if md5(btrim(source, E' \n\r\t')) <> '2312905874bc010c6f50adb16ede72b7'
    or (length(definition) - length(replace(definition, anchor, ''))) / length(anchor) <> 1 then
    raise exception 'oi_merge_accounts drift requires review before adding farmer outfits';
  end if;
  execute replace(definition, anchor,
    'and not exists(select 1 from benchmark_private.oi_farmer_outfits where account_id=source_account) ' ||
    'and not exists(select 1 from public.oi_profiles where id=source_account ' ||
    'and (public_name<>'''' or department<>'''' or admission_year<>'''')) ' || anchor);
end;
$patch$;

commit;
