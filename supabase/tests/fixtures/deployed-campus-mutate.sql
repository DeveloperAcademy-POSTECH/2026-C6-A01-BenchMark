-- Audited deployed RPC variant as of 2026-11-03. Synthetic schema compatibility fixture only.
alter table public.oi_stories add column height_meters double precision not null default 1.0;
alter table public.oi_stories add column heading_degrees double precision not null default 0.0;
CREATE OR REPLACE FUNCTION benchmark_private.oi_mutate(action text, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor uuid := auth.uid();
  target uuid;
  request public.oi_evidence_requests;
  permission public.oi_writing_grants;
  story public.oi_stories;
  wanted_status text;
  path text;
  expected integer;
  capacity integer;
  media jsonb;
  media_position integer := 0;
  campus_result jsonb;
begin
  if actor is null then raise exception 'Sign in required' using errcode='42501'; end if;
  if payload is null or jsonb_typeof(payload)<>'object' then raise exception 'Invalid payload' using errcode='22023'; end if;
  target := (payload->>'id')::uuid;
  if target is null then raise exception 'ID required' using errcode='22023'; end if;

  if action='save_campus_story' then
    -- Compose the existing owner/grant/revision checks atomically. No new approval bypass.
    select * into story from public.oi_stories where id=target;
    if found then
      if story.user_id<>actor then raise exception 'Not the owner' using errcode='42501'; end if;
      if story.status<>'draft' then
        campus_result := benchmark_private.oi_mutate('reopen_story',payload);
        payload := payload || jsonb_build_object('revision',(campus_result->>'revision')::integer);
      end if;
    end if;
    campus_result := benchmark_private.oi_mutate('save_story',payload);
    return benchmark_private.oi_mutate('submit_story',jsonb_build_object('id',target,'revision',(campus_result->>'revision')::integer));
  elsif action='start_evidence' then
    insert into public.oi_evidence_requests(id,user_id) values(target,actor) on conflict do nothing;
    select * into request from public.oi_evidence_requests where id=target and user_id=actor;
    if not found then raise exception 'Request unavailable' using errcode='42501'; end if;
    return to_jsonb(request);
  elsif action='submit_evidence' then
    select * into request from public.oi_evidence_requests where id=target and user_id=actor for update;
    if not found then raise exception 'Request unavailable' using errcode='42501'; end if;
    path := payload->>'object_path';
    if request.status='pending' and request.object_path=path then return to_jsonb(request); end if;
    if request.status<>'draft' or path is null or not starts_with(path,actor::text||'/'||target::text||'/')
      or not exists(select 1 from storage.objects where bucket_id='oi-evidence' and name=path) then
      raise exception 'Upload evidence before submitting' using errcode='22023';
    end if;
    update public.oi_evidence_requests set status='pending',object_path=path,submitted_at=now()
      where id=target returning * into request;
    return to_jsonb(request);
  elsif action='review_evidence' then
    if not benchmark_private.oi_is_operator() then raise exception 'Operator required' using errcode='42501'; end if;
    select * into request from public.oi_evidence_requests where id=target for update;
    if not found then raise exception 'Request unavailable' using errcode='22023'; end if;
    wanted_status := payload->>'status';
    if wanted_status not in ('approved','rejected','changes_requested','revoked') or wanted_status is null then
      raise exception 'Invalid decision' using errcode='22023';
    end if;
    if request.status<>'pending' and not(request.status='approved' and wanted_status='revoked') then
      raise exception 'Request changed; refresh before review' using errcode='40001';
    end if;
    if wanted_status='approved' then
      capacity := (payload->>'story_limit')::integer;
      if capacity is null or capacity<1 then raise exception 'Specify approved story count' using errcode='22023'; end if;
      insert into public.oi_writing_grants(evidence_id,user_id,story_limit) values(target,request.user_id,capacity);
    elsif wanted_status='revoked' then
      update public.oi_writing_grants set revoked_at=now() where evidence_id=target;
      update public.oi_stories set status='hidden',revision=revision+1,updated_at=now()
        where grant_id in(select id from public.oi_writing_grants where evidence_id=target) and status<>'deleted';
    end if;
    update public.oi_evidence_requests set status=wanted_status,reviewer_id=actor,
      review_note=payload->>'review_note',reviewed_at=now() where id=target returning * into request;
    insert into benchmark_private.oi_audit(actor_id,action,target_id) values(actor,action||':'||wanted_status,target);
    return to_jsonb(request);
  elsif action='save_story' then
    select * into permission from public.oi_writing_grants
      where id=(payload->>'grant_id')::uuid and user_id=actor and revoked_at is null for update;
    if not found then raise exception 'Writing approval required' using errcode='42501'; end if;
    select * into story from public.oi_stories where id=target for update;
    expected := (payload->>'revision')::integer;
    if found then
      if story.user_id<>actor or story.grant_id<>permission.id then raise exception 'Not the owner' using errcode='42501'; end if;
      if story.status<>'draft' or expected is distinct from story.revision then raise exception 'Story changed; refresh before editing' using errcode='40001'; end if;
    else
      if expected is distinct from 0 then raise exception 'New story revision must be zero' using errcode='40001'; end if;
      if (select count(*) from public.oi_stories where grant_id=permission.id)>=permission.story_limit then
        raise exception 'Approved story count exhausted' using errcode='42501';
      end if;
    end if;
    if not benchmark_private.oi_valid_location((payload->>'latitude')::double precision,(payload->>'longitude')::double precision) then
      raise exception 'Choose an outdoor point inside the campus' using errcode='22023';
    end if;
    if not exists(select 1 from public.oi_assets where id=payload->>'cucumber_asset' and kind='cucumber')
      or not exists(select 1 from public.oi_assets where id=payload->>'card_asset' and kind='card') then
      raise exception 'Unknown appearance asset' using errcode='22023';
    end if;
    insert into public.oi_stories(id,user_id,grant_id,region_id,title,body,theme,emotion,cucumber_name,cucumber_asset,card_asset,latitude,longitude,height_meters,heading_degrees)
      values(target,actor,permission.id,payload->>'region_id',payload->>'title',payload->>'body',payload->>'theme',payload->>'emotion',
        payload->>'cucumber_name',payload->>'cucumber_asset',payload->>'card_asset',(payload->>'latitude')::double precision,(payload->>'longitude')::double precision,
        coalesce((payload->>'height_meters')::double precision,story.height_meters,1.0),
        coalesce((payload->>'heading_degrees')::double precision,story.heading_degrees,0.0))
      on conflict(id) do update set title=excluded.title,body=excluded.body,theme=excluded.theme,emotion=excluded.emotion,
        region_id=excluded.region_id,cucumber_name=excluded.cucumber_name,cucumber_asset=excluded.cucumber_asset,
        card_asset=excluded.card_asset,latitude=excluded.latitude,longitude=excluded.longitude,
        height_meters=excluded.height_meters,heading_degrees=excluded.heading_degrees,
        revision=oi_stories.revision+1,updated_at=now()
      returning * into story;
    return to_jsonb(story);
  elsif action in ('attach_media','submit_story','reopen_story','delete_story','review_story') then
    select * into story from public.oi_stories where id=target;
    if not found then raise exception 'Story unavailable' using errcode='22023'; end if;
    select * into permission from public.oi_writing_grants where id=story.grant_id for share;
    select * into story from public.oi_stories where id=target for update;
    if not found then raise exception 'Story unavailable' using errcode='22023'; end if;
    if action='review_story' then
      if not benchmark_private.oi_is_operator() then raise exception 'Operator required' using errcode='42501'; end if;
    elsif story.user_id<>actor then raise exception 'Not the owner' using errcode='42501'; end if;
    if (payload->>'revision')::integer is distinct from story.revision then raise exception 'Story changed; refresh first' using errcode='40001'; end if;
    if story.status='deleted' then raise exception 'Story deleted' using errcode='22023'; end if;
    if action<>'delete_story' and permission.revoked_at is not null then raise exception 'Writing approval revoked' using errcode='42501'; end if;
    wanted_status := story.status;
    if action='attach_media' then
      if story.status<>'draft' or jsonb_typeof(payload->'paths') is distinct from 'array' then raise exception 'Draft media required' using errcode='22023'; end if;
      for media in select value from jsonb_array_elements(payload->'paths') loop
        path := media#>>'{}';
        if not starts_with(path,actor::text||'/'||target::text||'/')
          or not exists(select 1 from storage.objects where bucket_id='oi-story-media' and name=path) then
          raise exception 'Media not uploaded to this story' using errcode='22023';
        end if;
      end loop;
      delete from public.oi_story_media where story_id=target;
      for media in select value from jsonb_array_elements(payload->'paths') loop
        insert into public.oi_story_media(story_id,object_path,position) values(target,media#>>'{}',media_position);
        media_position := media_position+1;
      end loop;
    elsif action='submit_story' then
      if story.status<>'draft' then raise exception 'Only drafts can be submitted' using errcode='22023'; end if;
      wanted_status := 'pending';
    elsif action='reopen_story' then
      wanted_status := 'draft';
    elsif action='delete_story' then
      wanted_status := 'deleted';
    else
      wanted_status := payload->>'status';
      if wanted_status is null or wanted_status not in ('published','hidden') or story.status not in ('pending','published','hidden') then
        raise exception 'Invalid publication decision' using errcode='22023';
      end if;
    end if;
    update public.oi_stories set status=wanted_status,revision=revision+1,updated_at=now() where id=target returning * into story;
    insert into benchmark_private.oi_audit(actor_id,action,target_id) values(actor,action,target);
    return to_jsonb(story);
  elsif action in ('collect','remove_collection','favorite') then
    perform 1 from public.oi_stories where id=target and status='published' for share;
    if not found and action<>'remove_collection' then raise exception 'Published story unavailable' using errcode='42501'; end if;
    if action='collect' then
      insert into public.oi_collections(user_id,story_id) values(actor,target) on conflict do nothing;
    elsif action='remove_collection' then
      delete from public.oi_collections where user_id=actor and story_id=target;
    elsif (payload->>'enabled')::boolean is true then
      insert into public.oi_favorites(user_id,story_id) values(actor,target) on conflict do nothing;
    elsif (payload->>'enabled')::boolean is false then
      delete from public.oi_favorites where user_id=actor and story_id=target;
    else raise exception 'Favorite state required' using errcode='22023'; end if;
    return jsonb_build_object('id',target);
  end if;
  raise exception 'Unknown action' using errcode='22023';
end;
$function$;
