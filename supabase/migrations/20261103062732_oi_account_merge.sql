begin;

-- Auth identities remain intact. Application ownership has a separate canonical account.
create table benchmark_private.oi_account_members (
  auth_user_id uuid primary key references auth.users(id) on delete restrict,
  account_id uuid not null references public.oi_profiles(id) on delete restrict,
  session_cutover timestamptz,
  proof_session_ids uuid[] not null default '{}'
);
create index oi_account_members_account_idx on benchmark_private.oi_account_members(account_id);
alter table benchmark_private.oi_account_members enable row level security;
revoke all on benchmark_private.oi_account_members from public,anon,authenticated;
insert into benchmark_private.oi_account_members(auth_user_id,account_id) select id,id from public.oi_profiles;

create function benchmark_private.oi_initialize_account_membership() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  insert into benchmark_private.oi_account_members(auth_user_id,account_id) values(new.id,new.id) on conflict do nothing;
  return new;
end;
$$;
revoke all on function benchmark_private.oi_initialize_account_membership() from public,anon,authenticated;
create trigger oi_profile_account_membership after insert on public.oi_profiles
for each row execute function benchmark_private.oi_initialize_account_membership();

create function benchmark_private.oi_merge_session_allowed(actor uuid,cutover timestamptz,approved uuid[]) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare session_id text := auth.jwt()->>'session_id';
begin
  if cutover is null then return true; end if;
  if session_id is null or session_id !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then return false; end if;
  return exists(select 1 from auth.sessions s where s.id=session_id::uuid and s.user_id=actor
    and (s.id=any(approved) or s.created_at>=cutover));
end;
$$;
revoke all on function benchmark_private.oi_merge_session_allowed(uuid,timestamptz,uuid[]) from public,anon,authenticated;

create function benchmark_private.oi_account_id() returns uuid
language sql stable security definer set search_path='' as $$
  select m.account_id from benchmark_private.oi_account_members m where m.auth_user_id=auth.uid()
    and benchmark_private.oi_merge_session_allowed(m.auth_user_id,m.session_cutover,m.proof_session_ids);
$$;
revoke all on function benchmark_private.oi_account_id() from public;
grant execute on function benchmark_private.oi_account_id() to anon,authenticated;

-- Hold membership stable throughout every app mutation while merge takes update locks.
create function benchmark_private.oi_actor() returns uuid
language plpgsql volatile security definer set search_path='' as $$
declare member benchmark_private.oi_account_members;
begin
  select * into member from benchmark_private.oi_account_members where auth_user_id=auth.uid() for share;
  if not found or not benchmark_private.oi_merge_session_allowed(member.auth_user_id,member.session_cutover,member.proof_session_ids)
    then raise exception 'Sign in again to access this account' using errcode='PT401'; end if;
  return member.account_id;
end;
$$;
revoke all on function benchmark_private.oi_actor() from public,anon;
grant execute on function benchmark_private.oi_actor() to authenticated;

create function benchmark_private.oi_account_context() returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid := benchmark_private.oi_actor();
begin
  return jsonb_build_object('id',actor,'auth_user_id',auth.uid(),'email',null,'member_ids',
    (select jsonb_agg(auth_user_id order by auth_user_id) from benchmark_private.oi_account_members where account_id=actor),
    'account_providers',(select coalesce(jsonb_agg(provider order by provider),'[]'::jsonb) from (
      select distinct i.provider from auth.identities i join benchmark_private.oi_account_members m on m.auth_user_id=i.user_id
      where m.account_id=actor and i.provider in('google','apple')) verified_providers));
end;
$$;
revoke all on function benchmark_private.oi_account_context() from public,anon;
grant execute on function benchmark_private.oi_account_context() to authenticated;
create function public.oi_account_context() returns jsonb language sql security invoker set search_path='' as $$
  select benchmark_private.oi_account_context();
$$;
revoke all on function public.oi_account_context() from public,anon;
grant execute on function public.oi_account_context() to authenticated;
do $$ begin
  if (select md5(btrim(prosrc,E' \n\r\t')) from pg_proc where oid='public.oi_capabilities()'::regprocedure)<>'5e14f3fd030d40377e20644b2e5226dd'
    then raise exception 'oi_capabilities drift requires review before adding merge context'; end if;
end; $$;
create or replace function public.oi_capabilities() returns jsonb language sql security invoker set search_path='' as $$
  with context as (select benchmark_private.oi_account_context() value)
  select jsonb_build_object('operator',benchmark_private.oi_is_operator(),'coins_enabled',false,
    'account_merge_enabled',true,'account_id',value->'id','account_member_ids',value->'member_ids','account_providers',value->'account_providers') from context;
$$;

-- Keep old object prefixes stable; never move Storage objects during an account merge.
alter table public.oi_evidence_requests add column storage_owner_id uuid references auth.users(id) on delete restrict;
update public.oi_evidence_requests set storage_owner_id=user_id;
alter table public.oi_evidence_requests alter column storage_owner_id set not null;
alter table public.oi_stories add column storage_owner_id uuid references auth.users(id) on delete restrict;
update public.oi_stories set storage_owner_id=user_id;
alter table public.oi_stories alter column storage_owner_id set not null;
do $$
declare item record;
begin
  for item in select conname from pg_constraint where conrelid='public.oi_evidence_requests'::regclass
    and contype='c' and pg_get_constraintdef(oid) like '%object_path%' and pg_get_constraintdef(oid) like '%user_id%'
  loop execute format('alter table public.oi_evidence_requests drop constraint %I',item.conname); end loop;
end;
$$;
alter table public.oi_evidence_requests add constraint oi_evidence_storage_path_check
  check(object_path is null or object_path like storage_owner_id::text||'/'||id::text||'/%');

-- Update all app ownership policies, including evidence history, without widening public access.
do $$
declare item record;
begin
  for item in select * from pg_policies where schemaname='public' and tablename like 'oi\_%' escape '\'
  loop
    if item.qual is not null then execute format('alter policy %I on %I.%I using (%s)',item.policyname,item.schemaname,item.tablename,
      replace(item.qual,'auth.uid()','benchmark_private.oi_account_id()')); end if;
    if item.with_check is not null then execute format('alter policy %I on %I.%I with check (%s)',item.policyname,item.schemaname,item.tablename,
      replace(item.with_check,'auth.uid()','benchmark_private.oi_account_id()')); end if;
  end loop;
end;
$$;

drop policy oi_evidence_objects_read on storage.objects;
create policy oi_evidence_objects_read on storage.objects for select to authenticated using (
  bucket_id='oi-evidence' and ((select benchmark_private.oi_is_operator()) or exists(
    select 1 from public.oi_evidence_requests r where r.user_id=(select benchmark_private.oi_account_id())
      and r.storage_owner_id::text=(storage.foldername(name))[1] and r.id::text=(storage.foldername(name))[2])));
drop policy oi_evidence_objects_insert on storage.objects;
create policy oi_evidence_objects_insert on storage.objects for insert to authenticated with check (
  bucket_id='oi-evidence' and exists(select 1 from public.oi_evidence_requests r
    where r.user_id=(select benchmark_private.oi_account_id()) and r.status='draft'
      and r.storage_owner_id::text=(storage.foldername(name))[1] and r.id::text=(storage.foldername(name))[2]));
drop policy oi_media_objects_read on storage.objects;
create policy oi_media_objects_read on storage.objects for select to anon,authenticated using (
  bucket_id='oi-story-media' and exists(select 1 from public.oi_story_media m join public.oi_stories s on s.id=m.story_id
    where m.object_path=name and (s.status='published' or s.user_id=(select benchmark_private.oi_account_id()))));
drop policy oi_media_objects_insert on storage.objects;
create policy oi_media_objects_insert on storage.objects for insert to authenticated with check (
  bucket_id='oi-story-media' and exists(select 1 from public.oi_stories s
    where s.user_id=(select benchmark_private.oi_account_id()) and s.status='draft'
      and s.storage_owner_id::text=(storage.foldername(name))[1] and s.id::text=(storage.foldername(name))[2]));
drop policy oi_media_objects_staging_read on storage.objects;
create policy oi_media_objects_staging_read on storage.objects for select to authenticated using (
  bucket_id='oi-story-media' and exists(select 1 from public.oi_stories s
    where s.user_id=(select benchmark_private.oi_account_id()) and s.status='draft'
      and s.storage_owner_id::text=(storage.foldername(name))[1] and s.id::text=(storage.foldername(name))[2]));

-- Patch audited owning definitions in place; preserve deployed campus/height/heading behavior.
-- Unknown function drift aborts the entire migration instead of replacing business logic.
do $patch$
declare definition text; source text; anchor text;
begin
  select prosrc,pg_get_functiondef(oid) into source,definition from pg_proc where oid='benchmark_private.oi_mutate(text,jsonb)'::regprocedure;
  if md5(btrim(source,E' \n\r\t')) not in ('e81665d23ec01ab4dd7f73c8291b7a3b','ae86ba9c09543b254875f268496613df')
    then raise exception 'oi_mutate drift requires an ownership review before account merge migration'; end if;
  definition:=replace(definition,'actor uuid := auth.uid();','actor uuid := benchmark_private.oi_actor();');
  definition:=replace(definition,'oi_evidence_requests(id,user_id) values(target,actor)','oi_evidence_requests(id,user_id,storage_owner_id) values(target,actor,actor)');
  anchor:='starts_with(path,actor::text||''/''||target::text||''/'')';
  if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>2
    then raise exception 'Unexpected storage path checks in oi_mutate'; end if;
  -- Evidence and media are checked against their immutable original Storage owner.
  definition:=overlay(definition placing 'starts_with(path,request.storage_owner_id::text||''/''||target::text||''/'')'
    from strpos(definition,anchor) for length(anchor));
  definition:=replace(definition,anchor,'starts_with(path,story.storage_owner_id::text||''/''||target::text||''/'')');
  definition:=replace(definition,'oi_stories(id,user_id,grant_id,','oi_stories(id,user_id,storage_owner_id,grant_id,');
  definition:=replace(definition,'values(target,actor,permission.id,','values(target,actor,actor,permission.id,');
  if strpos(definition,'auth.uid()')>0 then raise exception 'Unreviewed identity checks remain in oi_mutate'; end if;
  execute definition;
end;
$patch$;


do $patch$
declare definition text; source text;
begin
  select prosrc,pg_get_functiondef(oid) into source,definition from pg_proc where oid='benchmark_private.oi_reopen_evidence(jsonb)'::regprocedure;
  if md5(btrim(source,E' \n\r\t'))<>'3205b8aa6f4fd06ec621def1e96b9b4b'
    then raise exception 'oi_reopen_evidence drift requires an ownership review before account merge migration'; end if;
  execute replace(definition,'auth.uid()','benchmark_private.oi_actor()');
end;
$patch$;


create table benchmark_private.oi_merge_operations (
  operation_id uuid primary key,
  challenge_id uuid not null unique default gen_random_uuid(),
  target_user_id uuid not null references auth.users(id),
  source_user_id uuid not null references auth.users(id),
  target_session_id uuid not null,
  source_session_id uuid not null,
  target_account_id uuid not null references public.oi_profiles(id),
  source_account_id uuid not null references public.oi_profiles(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now()+interval '5 minutes',
  consumed_at timestamptz,
  preview_counts jsonb,
  source_is_new boolean,
  result jsonb,
  check(target_user_id<>source_user_id)
);
create index oi_merge_operations_target_idx on benchmark_private.oi_merge_operations(target_user_id,created_at);
create index oi_merge_operations_source_idx on benchmark_private.oi_merge_operations(source_user_id,created_at);
alter table benchmark_private.oi_merge_operations enable row level security;
revoke all on benchmark_private.oi_merge_operations from public,anon,authenticated;

-- Only the Edge Function's service role may supply already-verified identity proofs.
create function public.oi_merge_accounts(p_action text,p_operation_id uuid,p_target_user_id uuid,p_source_user_id uuid,
  p_target_session_id uuid,p_source_session_id uuid,p_challenge_id uuid default null,p_consent boolean default false)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='15s' as $$
declare
  operation benchmark_private.oi_merge_operations;
  target_account uuid; source_account uuid; counts jsonb; cutover timestamptz; source_was_new boolean := false;
begin
  if p_action is null or p_action not in ('preview','confirm') or p_operation_id is null or p_target_user_id is null or p_source_user_id is null
    or p_target_user_id=p_source_user_id or p_target_session_id is null or p_source_session_id is null
    then raise exception 'invalid_merge_request' using errcode='22023'; end if;
  if p_action='confirm' and (p_consent is distinct from true or p_challenge_id is null)
    then raise exception 'merge_consent_required' using errcode='22023'; end if;
  if not exists(select 1 from auth.sessions where id=p_target_session_id and user_id=p_target_user_id
      and created_at between now()-interval '10 minutes' and now())
    or not exists(select 1 from auth.sessions where id=p_source_session_id and user_id=p_source_user_id
      and created_at between now()-interval '10 minutes' and now())
    then raise exception 'recent_login_required' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_operation_id::text,0));
  select * into operation from benchmark_private.oi_merge_operations where operation_id=p_operation_id for update;
  if found then
    if operation.target_user_id<>p_target_user_id or operation.source_user_id<>p_source_user_id
      or operation.target_session_id<>p_target_session_id or operation.source_session_id<>p_source_session_id
      then raise exception 'merge_operation_conflict' using errcode='40001'; end if;
    if p_action='confirm' and p_challenge_id is distinct from operation.challenge_id
      then raise exception 'merge_challenge_invalid' using errcode='42501'; end if;
    if operation.consumed_at is not null then
      if p_action='confirm' then return operation.result||jsonb_build_object('already_merged',true); end if;
      raise exception 'merge_operation_consumed' using errcode='40001';
    end if;
    if operation.expires_at<=now() then raise exception 'merge_challenge_expired' using errcode='40001'; end if;
  elsif p_action='confirm' then raise exception 'merge_challenge_invalid' using errcode='42501'; end if;

  -- Serializes opposing/cross-group merges and concurrent app mutations without long external calls.
  lock table benchmark_private.oi_account_members in share row exclusive mode;
  lock table benchmark_private.oi_operators in share mode;
  select account_id into target_account from benchmark_private.oi_account_members where auth_user_id=p_target_user_id;
  select account_id into source_account from benchmark_private.oi_account_members where auth_user_id=p_source_user_id;
  if target_account is null or source_account is null or target_account=source_account
    then raise exception 'accounts_already_unified' using errcode='40001'; end if;
  perform 1 from benchmark_private.oi_account_members where account_id in(target_account,source_account) order by auth_user_id for update;
  perform 1 from public.oi_profiles where id in(target_account,source_account) order by id for update;
  if exists(select 1 from benchmark_private.oi_operators o join benchmark_private.oi_account_members m on m.auth_user_id=o.user_id
      where m.account_id in(target_account,source_account))
    then raise exception 'operator_accounts_cannot_merge' using errcode='42501'; end if;
  if operation.operation_id is not null and (target_account<>operation.target_account_id or source_account<>operation.source_account_id)
    then raise exception 'merge_account_changed' using errcode='40001'; end if;
  if p_action='preview' then
    if operation.operation_id is null then
      if (select count(*) from benchmark_private.oi_merge_operations where created_at>now()-interval '1 minute'
          and (target_user_id=p_target_user_id or source_user_id=p_source_user_id))>=5
        then raise exception 'merge_rate_limited' using errcode='53300'; end if;
      insert into benchmark_private.oi_merge_operations(operation_id,target_user_id,source_user_id,target_session_id,source_session_id,target_account_id,source_account_id)
        values(p_operation_id,p_target_user_id,p_source_user_id,p_target_session_id,p_source_session_id,target_account,source_account) returning * into operation;
    end if;
  end if;
  counts:=jsonb_build_object(
      'stories',(select count(*) from public.oi_stories where user_id in(target_account,source_account)),
      'collections',(select count(distinct story_id) from public.oi_collections where user_id in(target_account,source_account)),
      'favorites',(select count(distinct story_id) from public.oi_favorites where user_id in(target_account,source_account)),
      'evidence',(select count(*) from public.oi_evidence_requests where user_id in(target_account,source_account)),
      'grants',(select count(*) from public.oi_writing_grants where user_id in(target_account,source_account)));
    -- A fresh unused account is a presentation hint, not proof of first-ever signup.
    -- PKCE callback and code exchange may be separated by more than one second.
    source_was_new := source_account=p_source_user_id
      and (select count(*)=1 from benchmark_private.oi_account_members where account_id=source_account)
      and exists(select 1 from auth.users u join auth.sessions s on s.user_id=u.id
        where u.id=p_source_user_id and s.id=p_source_session_id and s.created_at>=u.created_at
          and u.created_at>=now()-interval '10 minutes'
          and u.created_at>=s.created_at-interval '10 minutes'
          and not exists(select 1 from auth.sessions previous where previous.user_id=u.id and previous.id<>s.id))
      and exists(select 1 from public.oi_profiles p where p.id=source_account and p.nickname='농부'
        and p.school_id is null and p.farmer_asset='OiFarmer' and p.updated_at=p.created_at)
      and not exists(select 1 from public.oi_stories where user_id=source_account)
      and not exists(select 1 from public.oi_evidence_requests where user_id=source_account)
      and not exists(select 1 from public.oi_writing_grants where user_id=source_account)
      and not exists(select 1 from public.oi_collections where user_id=source_account)
      and not exists(select 1 from public.oi_favorites where user_id=source_account);
  if p_action='preview' then
    update benchmark_private.oi_merge_operations set preview_counts=counts,source_is_new=source_was_new where operation_id=p_operation_id;
    return jsonb_build_object('challenge_id',operation.challenge_id,'target_account_id',target_account,
      'source_account_id',source_account,'source_is_new',source_was_new,'expires_at',operation.expires_at,'counts',counts);
  end if;
  if operation.preview_counts is distinct from counts or operation.source_is_new is distinct from source_was_new
    then raise exception 'merge_account_changed' using errcode='40001'; end if;

  insert into public.oi_collections(user_id,story_id,created_at)
    select target_account,story_id,min(created_at) from public.oi_collections where user_id in(target_account,source_account) group by story_id
    on conflict(user_id,story_id) do update set created_at=least(oi_collections.created_at,excluded.created_at);
  insert into public.oi_favorites(user_id,story_id,created_at)
    select target_account,story_id,min(created_at) from public.oi_favorites where user_id in(target_account,source_account) group by story_id
    on conflict(user_id,story_id) do update set created_at=least(oi_favorites.created_at,excluded.created_at);
  delete from public.oi_favorites where user_id=source_account;
  delete from public.oi_collections where user_id=source_account;
  update public.oi_evidence_requests set user_id=target_account where user_id=source_account;
  update public.oi_writing_grants set user_id=target_account where user_id=source_account;
  update public.oi_stories set user_id=target_account where user_id=source_account;
  cutover:=clock_timestamp();
  update benchmark_private.oi_account_members set account_id=target_account,session_cutover=cutover,
    proof_session_ids=array[p_target_session_id,p_source_session_id] where account_id in(target_account,source_account);
  operation.result:=jsonb_build_object('account_id',target_account,'already_merged',false);
  update benchmark_private.oi_merge_operations set consumed_at=cutover,result=operation.result where operation_id=p_operation_id;
  insert into benchmark_private.oi_audit(actor_id,action,target_id) values(p_target_user_id,'merge_accounts',source_account);
  return operation.result;
end;
$$;
revoke all on function public.oi_merge_accounts(text,uuid,uuid,uuid,uuid,uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.oi_merge_accounts(text,uuid,uuid,uuid,uuid,uuid,uuid,boolean) to service_role;

commit;
