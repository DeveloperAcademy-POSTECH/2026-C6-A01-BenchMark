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

-- Reuse submission validation and row locking for both phases. Only a service-role
-- request can set the step used to prepare or publish a reviewed draft.
do $patch$
declare definition text := pg_get_functiondef('benchmark_private.oi_mutate(text,jsonb)'::regprocedure); change record;
begin
  for change in select * from (values
    ($old$  elsif action in ('attach_media','submit_story','reopen_story','delete_story','review_story') then$old$,
     $new$  elsif action in ('attach_media','submit_story','reopen_story','delete_story','review_story') then
    if action='review_story' and payload->>'status'='published'
      and benchmark_private.oi_auto_moderation_enabled() then
      raise exception 'Publication requires automatic review' using errcode='42501';
    end if;$new$),
    ($old$    elsif action='submit_story' then$old$,
     $new$    elsif action='submit_story' then
      if benchmark_private.oi_auto_moderation_enabled() and not (
        current_setting('role',true)='service_role'
        and coalesce(current_setting('benchmark.story_moderation_step',true),'') in ('prepare','publish')
      ) then
        raise exception 'Update the app to publish this story' using errcode='PT426';
      end if;$new$),
    ($old$      wanted_status := 'pending';
    elsif action='reopen_story' then$old$,
     $new$      wanted_status := 'pending';
      if current_setting('role',true)='service_role' then
        if current_setting('benchmark.story_moderation_step',true)='prepare' then
          return to_jsonb(story);
        elsif current_setting('benchmark.story_moderation_step',true)='publish' then
          wanted_status := 'published';
        end if;
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

-- The Edge Function validates the author JWT with Auth and forwards the verified
-- subject and session. The mutation still resolves the canonical account itself.
create function public.oi_moderate_story(p_user uuid, p_session uuid, p_submission jsonb, p_snapshot text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  actor uuid;
  story public.oi_stories;
  photo_paths text[];
  appearance_paths text[] := '{}';
  card_paths text[] := '{}';
  files jsonb;
  snapshot text;
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

  perform set_config('benchmark.story_moderation_step','prepare',true);
  select * into story from jsonb_populate_record(null::public.oi_stories,
    benchmark_private.oi_mutate('submit_story',p_submission));
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
    return jsonb_build_object('snapshot',snapshot,'title',story.title,'body',story.body,
      'cucumber_name',story.cucumber_name,'photos',photo_paths,'appearance',appearance_paths,'cards',card_paths);
  end if;
  if p_snapshot is distinct from snapshot then
    raise exception 'Story changed during automatic review' using errcode='40001';
  end if;

  perform set_config('benchmark.story_moderation_step','publish',true);
  return benchmark_private.oi_mutate('submit_story',p_submission);
exception when serialization_failure then
  raise exception 'Story changed during automatic review' using errcode='PT409';
end;
$$;
revoke all on function public.oi_moderate_story(uuid,uuid,jsonb,text) from public, anon, authenticated;
grant execute on function public.oi_moderate_story(uuid,uuid,jsonb,text) to service_role;

notify pgrst,'reload schema';
commit;
