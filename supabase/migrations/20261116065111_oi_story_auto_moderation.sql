begin;

-- Activate together with the Edge Function and the compatible client.
alter table benchmark_private.oi_story_creation_settings
  add column auto_moderation_enabled boolean not null default false;

create table benchmark_private.oi_story_moderation_quota (
  account_id uuid primary key references public.oi_profiles(id) on delete cascade,
  window_started_at timestamptz not null,
  attempts integer not null
);
alter table benchmark_private.oi_story_moderation_quota enable row level security;
revoke all on benchmark_private.oi_story_moderation_quota from public, anon, authenticated;

create table benchmark_private.oi_story_moderation_results (
  story_id uuid primary key references public.oi_stories(id) on delete cascade,
  revision integer not null,
  snapshot text not null,
  reason text,
  source text,
  check ((reason is null)=(source is null))
);
alter table benchmark_private.oi_story_moderation_results enable row level security;
revoke all on benchmark_private.oi_story_moderation_results from public, anon, authenticated;

create function benchmark_private.oi_auto_moderation_enabled() returns boolean
language sql stable security definer set search_path='' as $$
  select coalesce((
    select auto_moderation_enabled from benchmark_private.oi_story_creation_settings where singleton
  ), false);
$$;
revoke all on function benchmark_private.oi_auto_moderation_enabled() from public, anon, authenticated;

grant execute on function benchmark_private.oi_auto_moderation_enabled() to authenticated;

do $capability$
declare
  definition text := pg_get_functiondef('public.oi_capabilities()'::regprocedure);
  anchor constant text := '''story_card_cover_jpeg'',true';
begin
  if length(definition)-length(replace(definition,anchor,''))<>length(anchor) then
    raise exception 'oi_capabilities drift requires automatic review migration check';
  end if;
  execute replace(definition,anchor,anchor||',''auto_story_moderation'',benchmark_private.oi_auto_moderation_enabled()');
end; $capability$;

-- Keep the existing RPC contract. Only the private function can select a review phase.
do $patch$
declare definition text := pg_get_functiondef('benchmark_private.oi_mutate(text,jsonb)'::regprocedure); change record;
begin
  for change in select * from (values
    ($old$benchmark_private.oi_mutate(action text, payload jsonb)$old$,
     $new$benchmark_private.oi_mutate_internal(action text, payload jsonb, moderation_step text)$new$),
    ($old$  elsif action in ('attach_media','submit_story','reopen_story','delete_story','review_story') then$old$,
     $new$  elsif action in ('attach_media','submit_story','reopen_story','delete_story','review_story') then
    if action='review_story' and payload->>'status'='published'
      and benchmark_private.oi_auto_moderation_enabled() then
      raise exception 'Publication requires automatic review' using errcode='42501';
    end if;$new$),
    ($old$    elsif action='submit_story' then$old$,
     $new$    elsif action='submit_story' then
      if benchmark_private.oi_auto_moderation_enabled() and moderation_step is null then
        raise exception 'Update the app to publish this story' using errcode='PT426';
      end if;$new$),
    ($old$      wanted_status := 'pending';
    elsif action='reopen_story' then$old$,
     $new$      wanted_status := 'pending';
      if moderation_step='prepare' then
        return to_jsonb(story);
      elsif moderation_step='approve' then
        wanted_status := 'draft';
      elsif moderation_step='publish' then
        wanted_status := 'published';
      end if;
    elsif action='reopen_story' then$new$)
  ) as changes(before_text,after_text) loop
    if length(definition)-length(replace(definition,change.before_text,''))<>length(change.before_text) then
      raise exception 'oi_mutate drift requires automatic review migration check: %',left(btrim(change.before_text),96);
    end if;
    definition := replace(definition,change.before_text,change.after_text);
  end loop;
  execute definition;
end; $patch$;

revoke all on function benchmark_private.oi_mutate_internal(text,jsonb,text) from public, anon, authenticated, service_role;

create or replace function benchmark_private.oi_mutate(action text, payload jsonb) returns jsonb
language sql security definer set search_path='' as $$
  select benchmark_private.oi_mutate_internal(action,payload,null);
$$;

create function benchmark_private.oi_story_review_snapshot(p_submission jsonb) returns jsonb
language plpgsql set search_path='' as $$
declare
  story public.oi_stories;
  photo_paths text[];
  appearance_paths text[] := '{}';
  card_paths text[] := '{}';
  files jsonb;
  snapshot text;
begin
  select * into story from jsonb_populate_record(null::public.oi_stories,
    benchmark_private.oi_mutate_internal('submit_story',p_submission,'prepare'));
  select coalesce(array_agg(m.object_path order by m.position,m.id),'{}'::text[])
    into photo_paths from public.oi_story_media m where m.story_id=story.id;
  if cardinality(photo_paths) not between 1 and 3 or story.card_snapshot_id is null then
    raise exception 'Story requires photos and a card' using errcode='22023';
  end if;
  if story.cucumber_appearance is not null then
    perform benchmark_private.oi_check_cucumber_appearance(story,story.cucumber_appearance);
    appearance_paths := benchmark_private.oi_cucumber_appearance_paths(
      story.storage_owner_id,story.id,story.cucumber_appearance);
  end if;
  card_paths := benchmark_private.oi_story_card_parts(story.storage_owner_id,story.id,
    story.card_snapshot_id,story.card_snapshot_format,story.card_cover_type);
  -- User uploads are insert-only. Hold the reviewed objects through the publish
  -- transaction in case trusted maintenance replaces or removes one.
  perform 1 from storage.objects o where o.bucket_id='oi-story-media'
    and o.name=any(photo_paths||appearance_paths||card_paths) order by o.id for share;
  select jsonb_agg(jsonb_build_object('path',a.path,'id',o.id,'version',to_jsonb(o)->>'version',
    'updated_at',to_jsonb(o)->>'updated_at','metadata',o.metadata) order by a.ordinality)
    into files from unnest(photo_paths||appearance_paths||card_paths) with ordinality a(path,ordinality)
    join storage.objects o on o.bucket_id='oi-story-media' and o.name=a.path
    where o.metadata->>'mimetype' in ('image/jpeg','image/png');
  if coalesce(jsonb_array_length(files),0) <> cardinality(photo_paths||appearance_paths||card_paths) then
    raise exception 'Story images are unavailable' using errcode='22023';
  end if;
  snapshot := encode(sha256(convert_to(jsonb_build_array(to_jsonb(story),files)::text,'UTF8')),'hex');
  return jsonb_build_object('snapshot',snapshot,'title',story.title,'body',story.body,
    'cucumber_name',story.cucumber_name,'photos',photo_paths,'appearance',appearance_paths,'cards',card_paths);
end;
$$;
revoke all on function benchmark_private.oi_story_review_snapshot(jsonb) from public, anon, authenticated, service_role;

-- Record the AI verdict. Approval stores the exact reviewed artwork on the private draft.
create function public.oi_moderate_story(p_user uuid, p_session uuid, p_submission jsonb,
  p_snapshot text default null, p_reason text default null, p_source text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  actor uuid;
  draft jsonb;
  reviewed jsonb;
  target_story uuid := (p_submission->>'id')::uuid;
  review_revision integer := (p_submission->>'revision')::integer;
  final_snapshot text := p_snapshot;
  clock timestamptz := statement_timestamp();
begin
  if current_setting('role',true) is distinct from 'service_role' then
    raise exception 'Service role required' using errcode='42501';
  end if;
  if p_submission->'ai_review_consent_version' is distinct from '1'::jsonb then
    raise exception 'Automatic review consent required' using errcode='22023';
  end if;
  if not exists(select 1 from auth.sessions where id=p_session and user_id=p_user) then
    raise exception 'Sign in again' using errcode='PT401';
  end if;
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p_user,'session_id',p_session,'role','authenticated')::text,true);
  actor := benchmark_private.oi_actor();
  perform 1 from benchmark_private.oi_story_creation_settings where singleton for share;
  if not benchmark_private.oi_auto_moderation_enabled() then
    raise exception 'Automatic review unavailable' using errcode='PT503';
  end if;
  if benchmark_private.oi_content_restricted(actor) then
    raise exception 'Content publication restricted' using errcode='42501';
  end if;

  if (p_reason is null)<>(p_source is null)
    or (p_reason is not null and (p_snapshot is null or p_reason not in
      ('privacy','rights','unintelligible','profanity','harassment','sexual','violence','spam','fraud')
      or p_source not in ('story','photo','appearance','card'))) then
    raise exception 'Invalid review decision' using errcode='22023';
  end if;
  draft := benchmark_private.oi_story_review_snapshot(p_submission);
  if p_snapshot is null then
    insert into benchmark_private.oi_story_moderation_quota as quota
      values (actor,clock,1)
    on conflict (account_id) do update set
      window_started_at=case when quota.window_started_at<=clock-interval '1 minute' then clock else quota.window_started_at end,
      attempts=case when quota.window_started_at<=clock-interval '1 minute' then 1 else quota.attempts+1 end
    where quota.attempts<5 or quota.window_started_at<=clock-interval '1 minute';
    if not found then
      raise exception 'Too many publication requests' using errcode='PT429';
    end if;
    return draft;
  end if;
  if p_snapshot is distinct from draft->>'snapshot' then
    raise exception 'Story changed during automatic review' using errcode='40001';
  end if;
  if p_reason is null then
    reviewed := benchmark_private.oi_mutate_internal('submit_story',p_submission,'approve');
    review_revision := (reviewed->>'revision')::integer;
    final_snapshot := benchmark_private.oi_story_review_snapshot(jsonb_build_object(
      'id',target_story,'revision',review_revision))->>'snapshot';
  end if;

  insert into benchmark_private.oi_story_moderation_results as results(story_id,revision,snapshot,reason,source)
    values (target_story,review_revision,final_snapshot,p_reason,p_source)
  on conflict (story_id) do update set revision=excluded.revision,snapshot=excluded.snapshot,
    reason=excluded.reason,source=excluded.source;
  return jsonb_build_object('story_id',target_story,'revision',review_revision,
    'status',case when p_reason is null then 'approved' else 'rejected' end,
    'reason',p_reason,'source',p_source,'story',reviewed);
exception when serialization_failure then
  raise exception 'Story changed during automatic review' using errcode='PT409';
end;
$$;
revoke all on function public.oi_moderate_story(uuid,uuid,jsonb,text,text,text) from public, anon, authenticated;
grant execute on function public.oi_moderate_story(uuid,uuid,jsonb,text,text,text) to service_role;

create function public.oi_my_story_reviews() returns jsonb
language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object('story_id',s.id,'revision',r.revision,
    'status',case when r.reason is null then 'approved' else 'rejected' end,'reason',r.reason,'source',r.source)), '[]'::jsonb)
  from public.oi_stories s join benchmark_private.oi_story_moderation_results r
    on r.story_id=s.id and r.revision=s.revision
  where s.user_id=benchmark_private.oi_account_id() and s.status='draft';
$$;
revoke all on function public.oi_my_story_reviews() from public, anon, authenticated;
grant execute on function public.oi_my_story_reviews() to authenticated;

create function public.oi_plant_story(p_story uuid, p_revision integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  actor uuid := benchmark_private.oi_actor();
  submission jsonb := jsonb_build_object('id',p_story,'revision',p_revision);
  draft jsonb;
begin
  perform 1 from benchmark_private.oi_story_creation_settings where singleton for share;
  if not benchmark_private.oi_auto_moderation_enabled() then
    raise exception 'Automatic review unavailable' using errcode='PT503';
  end if;
  if benchmark_private.oi_content_restricted(actor) then
    raise exception 'Content publication restricted' using errcode='42501';
  end if;
  if not exists(select 1 from benchmark_private.oi_story_moderation_results r
    join public.oi_stories s on s.id=r.story_id
    where s.user_id=actor and r.story_id=p_story and r.revision=p_revision and r.reason is null) then
    raise exception 'Review the current story first' using errcode='PT409';
  end if;
  -- The snapshot helper locks the story first, serializing with edits and review completion.
  draft := benchmark_private.oi_story_review_snapshot(submission);
  if not exists(select 1 from benchmark_private.oi_story_moderation_results
    where story_id=p_story and revision=p_revision and reason is null and snapshot=draft->>'snapshot') then
    raise exception 'Review the current story first' using errcode='PT409';
  end if;
  return benchmark_private.oi_mutate_internal('submit_story',submission,'publish');
exception when serialization_failure then
  raise exception 'Review the current story first' using errcode='PT409';
end;
$$;
revoke all on function public.oi_plant_story(uuid,integer) from public, anon, authenticated;
grant execute on function public.oi_plant_story(uuid,integer) to authenticated;

notify pgrst,'reload schema';
commit;
