begin;

alter table benchmark_private.oi_education_stories
 add column review_reason text, add column review_source text;

create or replace function benchmark_private.oi_education_can_read(s benchmark_private.oi_education_stories) returns boolean
language sql stable security definer set search_path='' as $$
 select s.status<>'deleted' and benchmark_private.oi_education_account(s.owner_user_id) is not null
  and not benchmark_private.oi_account_is_deleting(benchmark_private.oi_education_account(s.owner_user_id))
  and (benchmark_private.oi_education_public(s)
   or benchmark_private.oi_education_account(s.owner_user_id)=benchmark_private.oi_account_id()
   or (s.status in ('published','hidden') and benchmark_private.oi_is_operator()));
$$;

create or replace function benchmark_private.oi_education_json(s benchmark_private.oi_education_stories) returns jsonb
language sql stable set search_path='' as $$
 select (to_jsonb(s)-'owner_user_id'-'consent_version'-'consent_at'-'review_reason'-'review_source')||jsonb_build_object(
  'origin','education','kind','교육지구 이야기','storage_owner_id',s.owner_user_id,
  'card_snapshot_format',2,'card_paths',benchmark_private.oi_education_card_paths(s.owner_user_id,s.id,s.card_snapshot_id))
  ||case when benchmark_private.oi_education_account(s.owner_user_id)=benchmark_private.oi_account_id() then
   jsonb_build_object('review_ready',s.status='pending' and s.consent_version='education-v2-2026-11-17' and s.review_reason is null,
    'review_reason',s.review_reason,'review_source',s.review_source) else '{}'::jsonb end
  ||case when benchmark_private.oi_is_operator() then jsonb_build_object('reports',
   (select coalesce(jsonb_agg(jsonb_build_object('reason',r.reason,'detail',r.detail,'created_at',r.created_at)),'[]'::jsonb)
    from benchmark_private.oi_education_reports r where r.story_id=s.id)) else '{}'::jsonb end;
$$;

create or replace function public.oi_education_stories(p_offset integer default 0,p_limit integer default 24,p_mine boolean default false,p_review boolean default false)
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
   and case when p_review then e.status in ('published','hidden')
    when p_mine then benchmark_private.oi_education_account(e.owner_user_id)=actor
    else benchmark_private.oi_education_public(e) end
   order by e.created_at desc,e.id limit p_limit offset p_offset) s);
end; $$;

create or replace function public.oi_education_mutate(p_action text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=benchmark_private.oi_actor(); target uuid; story benchmark_private.oi_education_stories; path text; paths text[];
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
  if not benchmark_private.oi_is_operator() or p_payload->>'status' is distinct from 'hidden' then
   raise exception 'Operators may only hide published stories' using errcode='42501'; end if;
 elsif story.id is not null and benchmark_private.oi_education_account(story.owner_user_id) is distinct from actor then
  raise exception 'Not the owner' using errcode='42501'; end if;
 if p_action not in ('delete','reopen','review') then
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
     or p_payload->'ai_review_consent_version' is distinct from '1'::jsonb
     or p_payload->>'consent_version' is distinct from 'education-v2-2026-11-17' then raise exception 'Automatic review consent required' using errcode='22023'; end if;
    story.card_snapshot_id:=(p_payload->>'card_snapshot_id')::uuid;
    perform benchmark_private.oi_education_check_files(story);
    story.status:='pending';story.consent_version:=p_payload->>'consent_version';story.consent_at:=now();
   elsif p_action='reopen' then
    story.status:='draft'; story.review_reason:=null; story.review_source:=null;
    story.consent_version:=null; story.consent_at:=null;
   elsif p_action='delete' then story.status:='deleted';
   elsif p_action='review' then
    if story.status<>'published' or p_payload->>'card_snapshot_id' is distinct from story.card_snapshot_id::text then
     raise exception 'Hide the current published story' using errcode='PT409'; end if;
    story.status:='hidden';
   end if;
   update benchmark_private.oi_education_stories set photo_paths=story.photo_paths,card_snapshot_id=story.card_snapshot_id,status=story.status,
    consent_version=story.consent_version,consent_at=story.consent_at,
    review_reason=story.review_reason,review_source=story.review_source,revision=revision+1,updated_at=now() where id=target returning * into story;
  end if;
 end if;
 insert into benchmark_private.oi_audit(actor_id,action,target_id) values(actor,'education:'||p_action||':'||story.status,target);
 return benchmark_private.oi_education_json(story);
end; $$;

-- Only the existing authenticated Edge Function can prepare and commit a review.
-- Pending artwork is immutable to users. Consent and the exact revision are
-- checked again after the provider responds and before public visibility changes.
create function public.oi_moderate_education_story(p_user uuid,p_session uuid,p_submission jsonb,
 p_snapshot text default null,p_reason text default null,p_source text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 actor uuid;
 target uuid:=(p_submission->>'id')::uuid;
 expected_revision integer:=(p_submission->>'revision')::integer;
 story benchmark_private.oi_education_stories;
 cards text[];
 snapshot text;
 clock timestamptz:=statement_timestamp();
begin
 if current_setting('role',true) is distinct from 'service_role' then
  raise exception 'Service role required' using errcode='42501'; end if;
 if not exists(select 1 from auth.sessions where id=p_session and user_id=p_user) then
  raise exception 'Sign in again' using errcode='PT401'; end if;
 if p_submission->'ai_review_consent_version' is distinct from '1'::jsonb or target is null then
  raise exception 'Automatic review consent required' using errcode='22023'; end if;
 if (p_reason is null)<>(p_source is null) or (p_reason is not null and
    (p_snapshot is null or p_reason not in ('privacy','rights','unintelligible','profanity','harassment','sexual','violence','spam','fraud')
     or p_source not in ('story','photo','card'))) then
  raise exception 'Invalid review decision' using errcode='22023'; end if;
 perform set_config('request.jwt.claim.sub',p_user::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_user,'session_id',p_session,'role','authenticated')::text,true);
 actor:=benchmark_private.oi_actor();
 perform 1 from benchmark_private.oi_story_creation_settings where singleton for share;
 if not benchmark_private.oi_unapproved_drafts_enabled() or benchmark_private.oi_content_restricted(actor) then
  raise exception 'Publication unavailable' using errcode='42501'; end if;

 perform pg_advisory_xact_lock(hashtextextended('oi_education:'||target::text,0));
 select * into story from benchmark_private.oi_education_stories where id=target for update;
 if not found or benchmark_private.oi_education_account(story.owner_user_id) is distinct from actor then
  raise exception 'Story unavailable' using errcode='42501'; end if;
 if story.status<>'pending' or story.revision is distinct from expected_revision or story.review_reason is not null
    or story.consent_version is distinct from 'education-v2-2026-11-17' or story.consent_at is null then
  raise exception 'Story changed; refresh first' using errcode='PT409'; end if;

 perform benchmark_private.oi_education_check_files(story);
 cards:=benchmark_private.oi_education_card_paths(story.owner_user_id,story.id,story.card_snapshot_id);
 snapshot:=encode(sha256(convert_to(to_jsonb(story)::text,'UTF8')),'hex');
 if p_snapshot is null then
  insert into benchmark_private.oi_story_moderation_quota as quota(account_id,window_started_at,attempts)
   values(actor,clock,1)
  on conflict(account_id) do update set
   window_started_at=case when quota.window_started_at<=clock-interval '1 minute' then clock else quota.window_started_at end,
   attempts=case when quota.window_started_at<=clock-interval '1 minute' then 1 else quota.attempts+1 end
  where quota.attempts<5 or quota.window_started_at<=clock-interval '1 minute';
  if not found then raise exception 'Too many publication requests' using errcode='PT429'; end if;
  return jsonb_build_object('snapshot',snapshot,'title',story.title,'body',story.body,'display_name',story.display_name,
   'photos',story.photo_paths,'appearance','[]'::jsonb,'cards',cards);
 end if;
 if p_snapshot is distinct from snapshot then
  raise exception 'Story changed during automatic review' using errcode='PT409'; end if;

 update benchmark_private.oi_education_stories set
  status=case when p_reason is null then 'published' else 'pending' end,
  review_reason=p_reason,review_source=p_source,revision=revision+1,updated_at=now()
  where id=target returning * into story;
 insert into benchmark_private.oi_audit(actor_id,action,target_id) values
  (actor,case when p_reason is null then 'education:ai_review:published' else 'education:ai_review:rejected' end,target);
 return jsonb_build_object('story_id',story.id,'revision',story.revision,
  'status',case when p_reason is null then 'approved' else 'rejected' end,
  'reason',p_reason,'source',p_source,'story',benchmark_private.oi_education_json(story)-'reports');
end; $$;
revoke all on function public.oi_moderate_education_story(uuid,uuid,jsonb,text,text,text) from public,anon,authenticated;
grant execute on function public.oi_moderate_education_story(uuid,uuid,jsonb,text,text,text) to service_role;

notify pgrst,'reload schema';
commit;
