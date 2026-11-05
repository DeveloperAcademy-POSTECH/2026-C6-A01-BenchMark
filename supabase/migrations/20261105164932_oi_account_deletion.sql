begin;

create table benchmark_private.oi_account_deletions (
  account_id uuid primary key references public.oi_profiles(id) on delete cascade
);
alter table benchmark_private.oi_account_deletions enable row level security;
revoke all on benchmark_private.oi_account_deletions from public, anon, authenticated;

create function benchmark_private.oi_account_is_deleting(p_account uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from benchmark_private.oi_account_deletions where account_id=p_account);
$$;
revoke all on function benchmark_private.oi_account_is_deleting(uuid) from public;
grant execute on function benchmark_private.oi_account_is_deleting(uuid) to anon, authenticated;

create or replace function benchmark_private.oi_account_id() returns uuid
language sql stable security definer set search_path='' as $$
  select m.account_id from benchmark_private.oi_account_members m where m.auth_user_id=auth.uid()
    and benchmark_private.oi_merge_session_allowed(m.auth_user_id,m.session_cutover,m.proof_session_ids)
    and not benchmark_private.oi_account_is_deleting(m.account_id);
$$;

create or replace function benchmark_private.oi_actor() returns uuid
language plpgsql volatile security definer set search_path='' as $$
declare member benchmark_private.oi_account_members;
begin
  select * into member from benchmark_private.oi_account_members where auth_user_id=auth.uid() for share;
  if not found or not benchmark_private.oi_merge_session_allowed(member.auth_user_id,member.session_cutover,member.proof_session_ids)
    then raise exception 'Sign in again to access this account' using errcode='PT401'; end if;
  if benchmark_private.oi_account_is_deleting(member.account_id) then
    raise exception 'Account deletion in progress' using errcode='PT409';
  end if;
  return member.account_id;
end;
$$;

create or replace function benchmark_private.oi_is_operator() returns boolean
language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and exists (
    select 1 from benchmark_private.oi_operators o join benchmark_private.oi_account_members m on m.auth_user_id=o.user_id
    where o.user_id=auth.uid() and not benchmark_private.oi_account_is_deleting(m.account_id)
  );
$$;

create function benchmark_private.oi_account_deletion_status() returns jsonb
language sql stable security definer set search_path='' as $$
  select coalesce((
    select jsonb_build_object('account_id',m.account_id,'member_ids',
      (select jsonb_agg(auth_user_id order by auth_user_id) from benchmark_private.oi_account_members where account_id=m.account_id))
    from benchmark_private.oi_account_members m where m.auth_user_id=auth.uid()
      and benchmark_private.oi_merge_session_allowed(m.auth_user_id,m.session_cutover,m.proof_session_ids)
      and benchmark_private.oi_account_is_deleting(m.account_id)
  ),'{}'::jsonb);
$$;
revoke all on function benchmark_private.oi_account_deletion_status() from public, anon, authenticated;
grant execute on function benchmark_private.oi_account_deletion_status() to authenticated;
create function public.oi_account_deletion_status() returns jsonb
language sql stable security invoker set search_path='' as $$
  select benchmark_private.oi_account_deletion_status();
$$;
revoke all on function public.oi_account_deletion_status() from public, anon, authenticated;
grant execute on function public.oi_account_deletion_status() to authenticated;

create function benchmark_private.oi_block_deletion_merge() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if benchmark_private.oi_account_is_deleting(old.account_id) or benchmark_private.oi_account_is_deleting(new.account_id) then
    raise exception 'Account deletion in progress' using errcode='PT409';
  end if;
  return new;
end;
$$;
revoke all on function benchmark_private.oi_block_deletion_merge() from public, anon, authenticated;
create trigger oi_block_deletion_merge before update on benchmark_private.oi_account_members
for each row execute function benchmark_private.oi_block_deletion_merge();

create policy oi_hide_deleting_stories on public.oi_stories as restrictive
for select to anon, authenticated using (not benchmark_private.oi_account_is_deleting(user_id));

-- Take the same membership row lock as regular mutations. The prepare
-- transaction waits for in-flight uploads and later uploads are rejected.
create function benchmark_private.oi_deletion_upload_allowed() returns boolean
language plpgsql security definer set search_path='' as $$
declare account uuid;
begin
  select account_id into account from benchmark_private.oi_account_members where auth_user_id=auth.uid() for share;
  return account is not null and not benchmark_private.oi_account_is_deleting(account);
end;
$$;
revoke all on function benchmark_private.oi_deletion_upload_allowed() from public, anon, authenticated;
grant execute on function benchmark_private.oi_deletion_upload_allowed() to authenticated;
create policy oi_block_deletion_upload on storage.objects as restrictive for insert to authenticated
with check (bucket_id not in ('oi-evidence','oi-story-media') or (select benchmark_private.oi_deletion_upload_allowed()));
create policy oi_block_deletion_upload_update on storage.objects as restrictive for update to authenticated
using (bucket_id not in ('oi-evidence','oi-story-media') or (select benchmark_private.oi_deletion_upload_allowed()))
with check (bucket_id not in ('oi-evidence','oi-story-media') or (select benchmark_private.oi_deletion_upload_allowed()));

-- The Edge Function verifies both tokens with Auth before passing these IDs.
-- Storage files are deleted through the Storage API, never by deleting metadata.
create function public.oi_delete_account(
  p_action text, p_user uuid, p_session uuid, p_proof_user uuid, p_proof_session uuid, p_account uuid
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare members uuid[]; stories uuid[]; evidence uuid[]; pending_files jsonb; has_apple boolean;
begin
  if p_action is null or p_action not in ('prepare','finish') or p_account is null then
    raise exception 'Invalid deletion action' using errcode='22023';
  end if;
  lock table benchmark_private.oi_account_members in share row exclusive mode;
  perform 1 from benchmark_private.oi_account_members where account_id=p_account order by auth_user_id for update;
  if not exists (select 1 from benchmark_private.oi_account_members m join auth.sessions s on s.user_id=m.auth_user_id
    where m.account_id=p_account and m.auth_user_id=p_user and s.id=p_session
      and (m.session_cutover is null or s.id=any(m.proof_session_ids) or s.created_at>=m.session_cutover))
    or not exists (select 1 from benchmark_private.oi_account_members m join auth.sessions s on s.user_id=m.auth_user_id
    where m.account_id=p_account and m.auth_user_id=p_proof_user and s.id=p_proof_session
      and s.created_at between now()-interval '10 minutes' and now()+interval '30 seconds'
      and (m.session_cutover is null or s.id=any(m.proof_session_ids) or s.created_at>=m.session_cutover))
    then raise exception 'Deletion requires a current account and recent login' using errcode='42501'; end if;
  select array_agg(auth_user_id) into members from benchmark_private.oi_account_members where account_id=p_account;
  select coalesce(array_agg(id),'{}') into stories from public.oi_stories where user_id=p_account;
  select coalesce(array_agg(id),'{}') into evidence from public.oi_evidence_requests where user_id=p_account;
  select exists(select 1 from auth.identities where user_id=any(members) and provider='apple') into has_apple;

  -- A member must never own a file referenced by a different app account.
  if exists(select 1 from public.oi_stories where storage_owner_id=any(members) and user_id<>p_account)
    or exists(select 1 from public.oi_evidence_requests where storage_owner_id=any(members) and user_id<>p_account)
    or exists(select 1 from storage.objects o where o.bucket_id not in ('oi-evidence','oi-story-media')
      and coalesce(to_jsonb(o)->>'owner_id',to_jsonb(o)->>'owner')=any(members::text[]))
    then raise exception 'Unrecognized storage ownership' using errcode='PT409'; end if;

  if p_action='prepare' then
    insert into benchmark_private.oi_account_deletions(account_id) values(p_account) on conflict do nothing;
  elsif not benchmark_private.oi_account_is_deleting(p_account) then
    raise exception 'Deletion has not been prepared' using errcode='PT409';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('bucket',bucket_id,'name',name)),'[]'::jsonb)
  into pending_files from (
    select o.bucket_id,o.name from storage.objects o where o.bucket_id in ('oi-evidence','oi-story-media') and (
      lower(split_part(o.name,'/',1))=any(members::text[])
      or coalesce(to_jsonb(o)->>'owner_id',to_jsonb(o)->>'owner')=any(members::text[])
      or (o.bucket_id='oi-story-media' and exists(select 1 from public.oi_story_media m where m.story_id=any(stories) and m.object_path=o.name))
      or (o.bucket_id='oi-evidence' and (exists(select 1 from public.oi_evidence_requests e where e.id=any(evidence) and e.object_path=o.name)
        or exists(select 1 from public.oi_evidence_history h where h.request_id=any(evidence) and h.object_path=o.name)))
    ) order by o.bucket_id,o.name limit 100
  ) files;
  if p_action='prepare' then return jsonb_build_object('files',pending_files); end if;
  if pending_files<>'[]'::jsonb then raise exception 'Storage deletion incomplete' using errcode='PT409'; end if;

  delete from benchmark_private.oi_audit where actor_id=any(members)
    or target_id=any(members) or target_id=any(stories) or target_id=any(evidence);
  delete from public.oi_collections where user_id=any(members) or story_id=any(stories);
  delete from public.oi_story_media where story_id=any(stories);
  delete from public.oi_stories where id=any(stories);
  delete from public.oi_writing_grants where user_id=p_account or evidence_id=any(evidence);
  delete from public.oi_evidence_history where request_id=any(evidence);
  delete from public.oi_evidence_requests where id=any(evidence);
  update public.oi_evidence_requests set reviewer_id=null where reviewer_id=any(members);
  update public.oi_evidence_history set reviewer_id=null where reviewer_id=any(members);
  delete from benchmark_private.oi_merge_operations where target_user_id=any(members) or source_user_id=any(members)
    or target_account_id=any(members) or source_account_id=any(members);
  delete from benchmark_private.oi_account_members where account_id=p_account;
  delete from auth.users where id=any(members);
  return jsonb_build_object('deleted',true,'apple_revocation_required',has_apple,'deleted_member_ids',members);
end;
$$;
revoke all on function public.oi_delete_account(text,uuid,uuid,uuid,uuid,uuid) from public, anon, authenticated;
grant execute on function public.oi_delete_account(text,uuid,uuid,uuid,uuid,uuid) to service_role;
notify pgrst,'reload schema';
commit;
