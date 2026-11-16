begin;

-- Education-district stories are a separate channel. No campus row, location,
-- AR placement, collection or donor/grant record is created by this feature.
create table benchmark_private.oi_education_stories (
 id uuid primary key,
 owner_user_id uuid not null references auth.users(id) on delete cascade,
 display_name text not null check(length(btrim(display_name)) between 1 and 40),
 title text not null check(length(btrim(title)) between 1 and 45),
 body text not null check(octet_length(body) between 1 and 1500 and length(btrim(body))>0),
 theme text not null check(length(btrim(theme)) between 1 and 30),
 emotion text not null check(length(btrim(emotion)) between 1 and 30),
 photo_paths text[] not null default '{}',
 card_snapshot_id uuid,
 status text not null default 'draft' check(status in ('draft','pending','published','hidden','deleted')),
 revision integer not null default 1 check(revision>0),
 consent_version text,
 consent_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index oi_education_stories_status_created on benchmark_private.oi_education_stories(status,created_at desc,id);
create index oi_education_stories_owner on benchmark_private.oi_education_stories(owner_user_id);
alter table benchmark_private.oi_education_stories enable row level security;
revoke all on benchmark_private.oi_education_stories from public,anon,authenticated;

create table benchmark_private.oi_education_reports (
 id uuid primary key default gen_random_uuid(),
 story_id uuid not null references benchmark_private.oi_education_stories(id) on delete cascade,
 reporter_user_id uuid not null references auth.users(id) on delete cascade,
 reason text not null check(reason in ('abuse','privacy','sexual','violence','other')),
 detail text not null check(length(detail)<=1000),
 created_at timestamptz not null default now(),
 unique(story_id,reporter_user_id)
);
alter table benchmark_private.oi_education_reports enable row level security;
revoke all on benchmark_private.oi_education_reports from public,anon,authenticated;

-- Resolve at read time so account merges preserve ownership and restrictions.
-- Referencing Auth members (not the removable source profile) preserves rows
-- during a merge; the existing account-deletion transaction deletes all members.
create function benchmark_private.oi_education_account(p_owner uuid) returns uuid
language sql stable security definer set search_path='' as $$
 select account_id from benchmark_private.oi_account_members where auth_user_id=p_owner;
$$;

create function benchmark_private.oi_education_public(s benchmark_private.oi_education_stories) returns boolean
language sql stable security definer set search_path='' as $$
 select s.status='published' and benchmark_private.oi_education_account(s.owner_user_id) is not null
  and not benchmark_private.oi_account_is_deleting(benchmark_private.oi_education_account(s.owner_user_id))
  and not benchmark_private.oi_content_restricted(benchmark_private.oi_education_account(s.owner_user_id));
$$;

create function benchmark_private.oi_education_can_read(s benchmark_private.oi_education_stories) returns boolean
language sql stable security definer set search_path='' as $$
 select s.status<>'deleted' and benchmark_private.oi_education_account(s.owner_user_id) is not null
  and not benchmark_private.oi_account_is_deleting(benchmark_private.oi_education_account(s.owner_user_id))
  and (benchmark_private.oi_education_public(s)
   or benchmark_private.oi_education_account(s.owner_user_id)=benchmark_private.oi_account_id()
   or benchmark_private.oi_is_operator());
$$;

create function benchmark_private.oi_education_card_paths(p_owner uuid,p_story uuid,p_snapshot uuid) returns text[]
language sql immutable strict set search_path='' as $$
 select array[p_owner::text||'/education/'||p_story::text||'/card/'||p_snapshot::text||'.png',
  p_owner::text||'/education/'||p_story::text||'/card/'||p_snapshot::text||'/back.png',
  p_owner::text||'/education/'||p_story::text||'/card/'||p_snapshot::text||'/front-preview.png',
  p_owner::text||'/education/'||p_story::text||'/card/'||p_snapshot::text||'/back-preview.png'];
$$;

create function benchmark_private.oi_education_json(s benchmark_private.oi_education_stories) returns jsonb
language sql stable set search_path='' as $$
 select (to_jsonb(s)-'owner_user_id'-'consent_version'-'consent_at')||jsonb_build_object(
  'origin','education','kind','교육지구 이야기','storage_owner_id',s.owner_user_id,
  'card_snapshot_format',2,'card_paths',benchmark_private.oi_education_card_paths(s.owner_user_id,s.id,s.card_snapshot_id))
  ||case when benchmark_private.oi_is_operator() then jsonb_build_object('reports',
   (select coalesce(jsonb_agg(jsonb_build_object('reason',r.reason,'detail',r.detail,'created_at',r.created_at)),'[]'::jsonb)
    from benchmark_private.oi_education_reports r where r.story_id=s.id)) else '{}'::jsonb end;
$$;

create function public.oi_education_stories(p_offset integer default 0,p_limit integer default 24,p_mine boolean default false,p_review boolean default false)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid;
begin
 if p_offset is null or p_offset<0 or p_offset>10000 or p_limit is null or p_limit<1 or p_limit>50
  or p_mine is null or p_review is null then raise exception 'Invalid page' using errcode='22023'; end if;
 if p_mine or p_review then
  actor:=benchmark_private.oi_account_id();
  if actor is null then raise exception 'Sign in required' using errcode='42501'; end if;
 end if;
 if p_review and not benchmark_private.oi_is_operator() then raise exception 'Operator required' using errcode='42501'; end if;
 return (select coalesce(jsonb_agg(benchmark_private.oi_education_json(s) order by s.created_at desc,s.id),'[]'::jsonb)
  from (select e.* from benchmark_private.oi_education_stories e where e.status<>'deleted'
   and benchmark_private.oi_education_can_read(e)
   and case when p_review then e.status in ('pending','published','hidden')
    when p_mine then benchmark_private.oi_education_account(e.owner_user_id)=actor
    else benchmark_private.oi_education_public(e) end
   order by e.created_at desc,e.id limit p_limit offset p_offset) s);
end; $$;

create function public.oi_education_story(p_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select benchmark_private.oi_education_json(s) from benchmark_private.oi_education_stories s
 where s.id=p_id and benchmark_private.oi_education_can_read(s);
$$;

create function benchmark_private.oi_education_storage_allowed(p_name text,p_write boolean default false) returns boolean
language plpgsql security definer set search_path='' as $$
declare parts text[]:=string_to_array(p_name,'/'); story benchmark_private.oi_education_stories; actor uuid;
begin
 if parts[2] is distinct from 'education' or p_name ~ '\.\.' or cardinality(parts) not in (5,6)
  or (parts[4]='photos' and (cardinality(parts)<>5 or parts[5]!~'^[0-9a-f-]{36}\.(jpg|png)$'))
  or (parts[4]='card' and not ((cardinality(parts)=5 and parts[5]~'^[0-9a-f-]{36}\.png$')
   or (cardinality(parts)=6 and parts[5]~'^[0-9a-f-]{36}$' and parts[6] in ('back.png','front-preview.png','back-preview.png'))))
  or parts[4] not in ('photos','card') then return false; end if;
 begin select * into story from benchmark_private.oi_education_stories where id=parts[3]::uuid;
 exception when invalid_text_representation then return false; end;
 if not found or parts[1] is distinct from story.owner_user_id::text
  or benchmark_private.oi_education_can_read(story) is not true then return false; end if;
 if p_write then
  actor:=benchmark_private.oi_actor();
  perform 1 from benchmark_private.oi_story_creation_settings where singleton for share;
  return story.status='draft' and benchmark_private.oi_education_account(story.owner_user_id)=actor
   and benchmark_private.oi_unapproved_drafts_enabled() and not benchmark_private.oi_content_restricted(actor);
 end if;
 if story.status='draft' and benchmark_private.oi_education_account(story.owner_user_id)=benchmark_private.oi_account_id() then return true; end if;
 return p_name=any(story.photo_paths) or p_name=any(benchmark_private.oi_education_card_paths(story.owner_user_id,story.id,story.card_snapshot_id));
end; $$;

create function benchmark_private.oi_education_check_files(s benchmark_private.oi_education_stories) returns void
language plpgsql set search_path='' as $$
declare path text;
begin
 if cardinality(s.photo_paths) not between 1 and 3 or s.card_snapshot_id is null then
  raise exception 'Story photo and both card sides are required' using errcode='22023'; end if;
 foreach path in array s.photo_paths loop
  if not exists(select 1 from storage.objects o where o.bucket_id='oi-story-media' and o.name=path
   and o.metadata->>'mimetype' in ('image/jpeg','image/png')
   and case when o.metadata->>'size' ~ '^[0-9]{1,8}$' then (o.metadata->>'size')::integer between 1 and 8388608 else false end)
   then raise exception 'Story photo is missing or invalid' using errcode='22023'; end if;
 end loop;
 foreach path in array benchmark_private.oi_education_card_paths(s.owner_user_id,s.id,s.card_snapshot_id) loop
  if not exists(select 1 from storage.objects o where o.bucket_id='oi-story-media' and o.name=path
   and o.metadata->>'mimetype'='image/png'
   and case when o.metadata->>'size' ~ '^[0-9]{1,8}$' then (o.metadata->>'size')::integer between 1 and 8388608 else false end)
   then raise exception 'Card artwork is missing or invalid' using errcode='22023'; end if;
 end loop;
end; $$;

create function public.oi_education_mutate(p_action text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=benchmark_private.oi_actor(); target uuid; story benchmark_private.oi_education_stories; path text; paths text[]; wanted text;
begin
 if actor is null then raise exception 'Sign in required' using errcode='42501'; end if;
 if p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Invalid payload' using errcode='22023'; end if;
 target:=(p_payload->>'id')::uuid;
 if target is null or p_action is null or p_action not in ('save','attach_media','submit','reopen','delete','review') then
  raise exception 'Invalid education story action' using errcode='22023'; end if;
 perform 1 from benchmark_private.oi_story_creation_settings where singleton for share;
 perform pg_advisory_xact_lock(hashtextextended('oi_education:'||target::text,0));
 select * into story from benchmark_private.oi_education_stories where id=target for update;
 if p_action='review' then
  if not benchmark_private.oi_is_operator() then raise exception 'Operator required' using errcode='42501'; end if;
 elsif story.id is not null and benchmark_private.oi_education_account(story.owner_user_id) is distinct from actor then
  raise exception 'Not the owner' using errcode='42501'; end if;
 if p_action not in ('delete','reopen','review') or (p_action='review' and p_payload->>'status'='published') then
  if not benchmark_private.oi_unapproved_drafts_enabled() then raise exception 'Story creation is paused; drafts are preserved' using errcode='42501'; end if;
  if benchmark_private.oi_content_restricted(coalesce(benchmark_private.oi_education_account(story.owner_user_id),actor)) then
   raise exception 'Content publication restricted' using errcode='42501'; end if;
 end if;
 if story.id is null then
  if p_action<>'save' or (p_payload->>'revision')::integer is distinct from 0 then raise exception 'New draft revision must be zero' using errcode='PT409'; end if;
  insert into benchmark_private.oi_education_stories(id,owner_user_id,display_name,title,body,theme,emotion)
   values(target,auth.uid(),p_payload->>'display_name',p_payload->>'title',p_payload->>'body',p_payload->>'theme',p_payload->>'emotion') returning * into story;
 else
  if story.status='deleted' or (p_payload->>'revision')::integer is distinct from story.revision then
   raise exception 'Story changed; refresh first' using errcode='PT409'; end if;
  if p_action='save' then
   if story.status<>'draft' then raise exception 'Reopen the story before editing' using errcode='PT409'; end if;
   update benchmark_private.oi_education_stories set display_name=p_payload->>'display_name',title=p_payload->>'title',body=p_payload->>'body',
    theme=p_payload->>'theme',emotion=p_payload->>'emotion',revision=revision+1,updated_at=now() where id=target returning * into story;
  else
   if p_action='attach_media' then
    if story.status<>'draft' or jsonb_typeof(p_payload->'paths') is distinct from 'array' then raise exception 'Draft photos required' using errcode='22023'; end if;
    select array_agg(value) into paths from jsonb_array_elements_text(p_payload->'paths');
    if coalesce(cardinality(paths),0) not between 1 and 3 then raise exception 'Choose one to three photos' using errcode='22023'; end if;
    foreach path in array paths loop
     if not starts_with(path,story.owner_user_id::text||'/education/'||story.id::text||'/photos/')
      or not benchmark_private.oi_education_storage_allowed(path,true)
      or not exists(select 1 from storage.objects where bucket_id='oi-story-media' and name=path) then raise exception 'Photo not uploaded to this story' using errcode='22023'; end if;
    end loop;
    story.photo_paths:=paths;
   elsif p_action='submit' then
    if story.status<>'draft' then raise exception 'Only drafts can be submitted' using errcode='PT409'; end if;
    if p_payload->'publication_consent' is distinct from 'true'::jsonb or p_payload->'rights_consent' is distinct from 'true'::jsonb
     or p_payload->>'consent_version' is distinct from 'education-v1-2026-11-16' then raise exception 'Publication consent required' using errcode='22023'; end if;
    story.card_snapshot_id:=(p_payload->>'card_snapshot_id')::uuid;
    perform benchmark_private.oi_education_check_files(story);
    story.status:='pending';story.consent_version:=p_payload->>'consent_version';story.consent_at:=now();
   elsif p_action='reopen' then story.status:='draft';
   elsif p_action='delete' then story.status:='deleted';
   elsif p_action='review' then
    wanted:=p_payload->>'status';
    if wanted is null or wanted not in ('published','hidden') or story.status not in ('pending','published','hidden')
     or p_payload->>'card_snapshot_id' is distinct from story.card_snapshot_id::text then raise exception 'Review current card artwork first' using errcode='PT409'; end if;
    if wanted='published' then
     if benchmark_private.oi_education_account(story.owner_user_id) is null
      or benchmark_private.oi_account_is_deleting(benchmark_private.oi_education_account(story.owner_user_id)) then raise exception 'Story unavailable' using errcode='42501'; end if;
     perform benchmark_private.oi_education_check_files(story);
    end if;
    story.status:=wanted;
   end if;
   update benchmark_private.oi_education_stories set photo_paths=story.photo_paths,card_snapshot_id=story.card_snapshot_id,status=story.status,
    consent_version=story.consent_version,consent_at=story.consent_at,revision=revision+1,updated_at=now() where id=target returning * into story;
  end if;
 end if;
 insert into benchmark_private.oi_audit(actor_id,action,target_id) values(actor,'education:'||p_action||':'||story.status,target);
 return benchmark_private.oi_education_json(story);
end; $$;

create function public.oi_education_report(p_story uuid,p_reason text,p_detail text default '') returns void
language plpgsql security definer set search_path='' as $$
declare actor uuid:=benchmark_private.oi_actor();
begin
 if actor is null or not exists(select 1 from benchmark_private.oi_education_stories s where s.id=p_story and benchmark_private.oi_education_public(s)) then
  raise exception 'Published story unavailable' using errcode='42501'; end if;
 insert into benchmark_private.oi_education_reports(story_id,reporter_user_id,reason,detail) values(p_story,auth.uid(),p_reason,p_detail)
  on conflict(story_id,reporter_user_id) do update set reason=excluded.reason,detail=excluded.detail,created_at=now();
 insert into benchmark_private.oi_audit(actor_id,action,target_id) values(actor,'education:report',p_story);
end; $$;

create function benchmark_private.oi_education_cleanup_audit() returns trigger
language plpgsql security definer set search_path='' as $$
begin delete from benchmark_private.oi_audit where target_id=old.id;return old;end; $$;
create trigger oi_education_cleanup_audit after delete on benchmark_private.oi_education_stories
 for each row execute function benchmark_private.oi_education_cleanup_audit();

revoke all on function benchmark_private.oi_education_account(uuid),benchmark_private.oi_education_public(benchmark_private.oi_education_stories),
 benchmark_private.oi_education_can_read(benchmark_private.oi_education_stories),benchmark_private.oi_education_card_paths(uuid,uuid,uuid),
 benchmark_private.oi_education_json(benchmark_private.oi_education_stories),benchmark_private.oi_education_storage_allowed(text,boolean),
 benchmark_private.oi_education_check_files(benchmark_private.oi_education_stories),benchmark_private.oi_education_cleanup_audit() from public,anon,authenticated;
grant execute on function benchmark_private.oi_education_storage_allowed(text,boolean) to anon,authenticated;
revoke all on function public.oi_education_stories(integer,integer,boolean,boolean),public.oi_education_story(uuid),public.oi_education_mutate(text,jsonb),
 public.oi_education_report(uuid,text,text) from public,anon,authenticated;
grant execute on function public.oi_education_stories(integer,integer,boolean,boolean),public.oi_education_story(uuid) to anon,authenticated;
grant execute on function public.oi_education_mutate(text,jsonb),public.oi_education_report(uuid,text,text) to authenticated;

-- Preserve the existing restrictive campus gate; only this separate, validated
-- namespace can take the education branch. No campus upload is made public.
alter policy oi_media_writing_access on storage.objects with check (
 bucket_id<>'oi-story-media' or case when (storage.foldername(name))[2]='education'
  then benchmark_private.oi_education_storage_allowed(name,true)
  else benchmark_private.oi_can_upload_story_media((storage.foldername(name))[2]) end);
create policy oi_education_media_upload on storage.objects for insert to authenticated
 with check(bucket_id='oi-story-media' and benchmark_private.oi_education_storage_allowed(name,true));
create policy oi_education_media_read on storage.objects for select to anon,authenticated
 using(bucket_id='oi-story-media' and benchmark_private.oi_education_storage_allowed(name,false));

notify pgrst,'reload schema';
commit;
