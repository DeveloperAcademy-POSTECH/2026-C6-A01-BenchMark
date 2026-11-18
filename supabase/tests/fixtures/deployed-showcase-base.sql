-- Deployed base captured 2026-11-18; function source only, no user data.
CREATE OR REPLACE FUNCTION benchmark_private.oi_mutate_continuation_base(action text, payload jsonb, moderation_step text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor uuid := benchmark_private.oi_actor();
  target uuid;
  story public.oi_stories;
  wanted_status text;
  path text;
  expected integer;
  media jsonb;
  media_position integer := 0;
  campus_result jsonb;
begin
  if actor is null then raise exception 'Sign in required' using errcode='42501'; end if;
  if payload is null or jsonb_typeof(payload)<>'object' then raise exception 'Invalid payload' using errcode='22023'; end if;
  target := (payload->>'id')::uuid;
  if target is null then raise exception 'ID required' using errcode='22023'; end if;
  if action in ('save_story','save_campus_story','attach_media','submit_story','reopen_story','delete_story','review_story') then
    perform 1 from benchmark_private.oi_story_creation_settings where singleton for share;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('oi_story:'||target::text,0));
  end if;

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
  elsif action in ('start_evidence','submit_evidence','review_evidence','reopen_evidence') then
    raise sqlstate 'PT410' using message='Donation evidence intake is closed';
  elsif action='save_story' then
    if not benchmark_private.oi_unapproved_drafts_enabled() then
      raise exception 'Story creation is paused; saved drafts and photos are preserved' using errcode='42501';
    end if;
    select * into story from public.oi_stories where id=target for update;
    expected := (payload->>'revision')::integer;
    if found then
      if story.user_id<>actor then raise exception 'Not the owner' using errcode='42501'; end if;
      if story.status<>'draft' or expected is distinct from story.revision then raise exception 'Story changed; refresh before editing' using errcode='PT409'; end if;
    else
      if expected is distinct from 0 then raise exception 'New story revision must be zero' using errcode='40001'; end if;
    end if;
    if not benchmark_private.oi_valid_location((payload->>'latitude')::double precision,(payload->>'longitude')::double precision) then
      raise exception 'Choose an outdoor point inside the campus' using errcode='22023';
    end if;
    if not exists(select 1 from public.oi_assets where id=payload->>'cucumber_asset' and kind='cucumber')
      or not exists(select 1 from public.oi_assets where id=payload->>'card_asset' and kind='card') then
      raise exception 'Unknown appearance asset' using errcode='22023';
    end if;
    if (payload->>'height_meters')::float8 in ('NaN'::float8,'Infinity'::float8,'-Infinity'::float8)
      or (payload->>'heading_degrees')::float8 in ('NaN'::float8,'Infinity'::float8,'-Infinity'::float8) then
      raise exception 'Story placement geometry must be finite' using errcode='22023';
    end if;
    insert into public.oi_stories(id,user_id,storage_owner_id,grant_id,region_id,title,body,theme,emotion,cucumber_name,cucumber_asset,card_asset,latitude,longitude,height_meters,heading_degrees)
      values(target,actor,actor,null,payload->>'region_id',payload->>'title',payload->>'body',payload->>'theme',payload->>'emotion',
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
    select * into story from public.oi_stories where id=target for update;
    if not found then raise exception 'Story unavailable' using errcode='22023'; end if;
    if action='review_story' then
      if not benchmark_private.oi_is_operator() then raise exception 'Operator required' using errcode='42501'; end if;
    elsif story.user_id<>actor then raise exception 'Not the owner' using errcode='42501'; end if;
    if (payload->>'revision')::integer is distinct from story.revision then raise exception 'Story changed; refresh first' using errcode='40001'; end if;
    if story.status='deleted' then raise exception 'Story deleted' using errcode='22023'; end if;
    if not benchmark_private.oi_unapproved_drafts_enabled()
      and (action in ('attach_media','submit_story') or (action='review_story' and payload->>'status'='published')) then
      raise exception 'Story creation is paused; saved drafts and photos are preserved' using errcode='42501';
    end if;
    wanted_status := story.status;
    if action='attach_media' then
      if story.status<>'draft' or jsonb_typeof(payload->'paths') is distinct from 'array' then raise exception 'Draft media required' using errcode='22023'; end if;
      for media in select value from jsonb_array_elements(payload->'paths') loop
        path := media#>>'{}';
        if (storage.foldername(path))[3] in ('appearance','card') or not starts_with(path,story.storage_owner_id::text||'/'||target::text||'/')
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
      if benchmark_private.oi_auto_moderation_enabled() and moderation_step is null then
        raise exception 'Update the app to publish this story' using errcode='PT426';
      end if;
      if story.status<>'draft' then raise exception 'Only drafts can be submitted' using errcode='22023'; end if;
      if payload ? 'cucumber_appearance' then
        perform benchmark_private.oi_check_cucumber_appearance(story,payload->'cucumber_appearance');
        story.cucumber_appearance := payload->'cucumber_appearance';
      end if;
      if payload ? 'card_snapshot_id' then
        declare
          next_snapshot uuid := (payload->>'card_snapshot_id')::uuid;
          next_format integer := coalesce((payload->>'card_snapshot_format')::integer,1);
          next_cover_type text;
        begin
          if next_format not in (1,2,3) or (next_format>=2 and next_snapshot is null) then
            raise exception 'Invalid card format' using errcode='22023';
          end if;
          if next_format=3 then
            next_cover_type := case
              when payload ? 'card_cover_type' then payload->>'card_cover_type'
              when next_snapshot=story.card_snapshot_id and story.card_snapshot_format=3 then story.card_cover_type
              else 'png' end;
            if next_cover_type is null or next_cover_type not in ('png','jpeg')
              or (payload ? 'card_cover_type' and jsonb_typeof(payload->'card_cover_type') is distinct from 'string') then
              raise exception 'Invalid card cover type' using errcode='22023';
            end if;
          elsif payload ? 'card_cover_type' and payload->'card_cover_type'<>'null'::jsonb then
            raise exception 'Only format 3 has a card cover' using errcode='22023';
          end if;
          if next_snapshot=story.card_snapshot_id and next_cover_type is distinct from story.card_cover_type then
            raise exception 'Changed card cover requires a new snapshot' using errcode='22023';
          end if;
          story.card_snapshot_id := next_snapshot;
          story.card_snapshot_format := next_format;
          story.card_cover_type := next_cover_type;
        end;
      elsif payload ? 'card_cover_type' then
        if payload->>'card_cover_type' is distinct from story.card_cover_type
          or (story.card_snapshot_format=3 and jsonb_typeof(payload->'card_cover_type') is distinct from 'string') then
          raise exception 'Changed card cover requires a new snapshot' using errcode='22023';
        end if;
      end if;
      if story.card_snapshot_id is not null or payload ? 'card_snapshot_id' then
        perform benchmark_private.oi_check_story_card(story);
      end if;
      wanted_status := 'pending';
      if moderation_step='prepare' then
        return to_jsonb(story);
      elsif moderation_step='approve' then
        wanted_status := 'draft';
      elsif moderation_step='publish' then
        wanted_status := 'published';
      end if;
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
    if action='review_story' and wanted_status='published' and story.cucumber_appearance is not null then
      if payload->>'appearance_id' is distinct from story.cucumber_appearance->>'id' then
        raise exception 'Review the current cucumber appearance first' using errcode='40001';
      end if;
      perform benchmark_private.oi_check_cucumber_appearance(story,story.cucumber_appearance);
    end if;
    if action='review_story' and wanted_status='published' and story.card_snapshot_id is not null then
      if (story.card_cover_type='jpeg' and
          (jsonb_typeof(payload->'card_cover_type') is distinct from 'string'
            or payload->>'card_cover_type' is distinct from story.card_cover_type))
        or (payload ? 'card_cover_type' and payload->>'card_cover_type' is distinct from story.card_cover_type) then
        raise exception 'Review the current cover with an updated operator app' using errcode='40001';
      end if;
      if payload->>'card_snapshot_id' is distinct from story.card_snapshot_id::text
        or (story.card_snapshot_format>=2 and coalesce(payload->>'card_snapshot_format','')<>story.card_snapshot_format::text) then
        raise exception 'Review the current story card first' using errcode='40001';
      end if;
      perform benchmark_private.oi_check_story_card(story);
    end if;
    update public.oi_stories set status=wanted_status,cucumber_appearance=story.cucumber_appearance,
      card_snapshot_id=story.card_snapshot_id,card_snapshot_format=story.card_snapshot_format,card_cover_type=story.card_cover_type,
      revision=revision+1,updated_at=now() where id=target returning * into story;
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
$function$
