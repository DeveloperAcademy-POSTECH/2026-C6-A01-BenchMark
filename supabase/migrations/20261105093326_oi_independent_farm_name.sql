begin;

-- Farm names are independent product data. Existing and new accounts start with
-- the same default; legacy nickname values are neither copied nor rewritten.
alter table public.oi_profiles add column farm_name text not null default '오이';
alter table public.oi_profiles add constraint oi_profiles_farm_name_check check (
  farm_name is nfc normalized and char_length(farm_name) between 1 and 6
);

create function benchmark_private.oi_normalize_farm_name() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  -- Match Foundation whitespace trimming, then count normalized Unicode scalars.
  new.farm_name := normalize(btrim(new.farm_name,
    E' \t\n\r\f\013' || U&'\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000'), NFC);
  if tg_op = 'UPDATE' then new.updated_at := clock_timestamp(); end if;
  return new;
end;
$$;
revoke all on function benchmark_private.oi_normalize_farm_name() from public, anon, authenticated;
create trigger oi_profile_farm_name before insert or update of farm_name on public.oi_profiles
for each row execute function benchmark_private.oi_normalize_farm_name();

-- Keep the existing canonical-account UPDATE policy and other column grants.
grant update(farm_name) on public.oi_profiles to authenticated;

-- A customized farm must not be presented as an unused new login method.
-- Preserve the rest of the audited merge transaction, including data ownership.
do $patch$
declare source text; definition text; anchor text := 'and p.nickname=''농부''';
begin
  select prosrc, pg_get_functiondef(oid) into source, definition from pg_proc
    where oid = 'public.oi_merge_accounts(text,uuid,uuid,uuid,uuid,uuid,uuid,boolean)'::regprocedure;
  if md5(btrim(source, E' \n\r\t')) <> '42851cb449affe686a058a31fa203ca0'
    or (length(definition) - length(replace(definition, anchor, ''))) / length(anchor) <> 1 then
    raise exception 'oi_merge_accounts drift requires review before adding farm names';
  end if;
  execute replace(definition, anchor, anchor || ' and p.farm_name=''오이''');
end;
$patch$;

commit;
