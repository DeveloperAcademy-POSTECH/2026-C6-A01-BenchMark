begin;

create function benchmark_private.oi_polygon_contains(polygon jsonb, point_x double precision, point_y double precision)
returns boolean language plpgsql immutable set search_path = '' as $$
declare
  inside boolean := false;
  previous integer := jsonb_array_length(polygon)-1;
  vertex integer;
  first_x double precision;
  first_y double precision;
  second_x double precision;
  second_y double precision;
begin
  if jsonb_array_length(polygon)<3 then return false; end if;
  for vertex in 0..jsonb_array_length(polygon)-1 loop
    first_x := (polygon->vertex->>0)::double precision;
    first_y := (polygon->vertex->>1)::double precision;
    second_x := (polygon->previous->>0)::double precision;
    second_y := (polygon->previous->>1)::double precision;
    if (first_y>point_y)<>(second_y>point_y) then
      if point_x < (second_x-first_x)*(point_y-first_y)/(second_y-first_y)+first_x then
        inside := not inside;
      end if;
    end if;
    previous := vertex;
  end loop;
  return inside;
end;
$$;
revoke all on function benchmark_private.oi_polygon_contains(jsonb,double precision,double precision) from public,anon,authenticated;

create function benchmark_private.oi_valid_location(latitude double precision, longitude double precision)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  geometry jsonb;
  point_x double precision;
  point_y double precision;
  polygon jsonb;
  inside boolean := false;
begin
  if latitude is null or longitude is null or not(latitude between -90 and 90 and longitude between -180 and 180) then return false; end if;
  select definition into strict geometry from benchmark_private.oi_geometry where id='postech';
  point_x := (longitude-(geometry->'origin'->>0)::double precision)*111320*cos(radians((geometry->'origin'->>1)::double precision))*(geometry->>'scale')::double precision;
  point_y := (latitude-(geometry->'origin'->>1)::double precision)*111320*(geometry->>'scale')::double precision;
  for polygon in select value from jsonb_array_elements(geometry->'bounds') loop
    inside := inside or benchmark_private.oi_polygon_contains(polygon,point_x,point_y);
  end loop;
  if not inside then return false; end if;
  for polygon in select value from jsonb_array_elements(geometry->'buildings') loop
    if benchmark_private.oi_polygon_contains(polygon,point_x,point_y) then return false; end if;
  end loop;
  return true;
end;
$$;
revoke all on function benchmark_private.oi_valid_location(double precision,double precision) from public,anon,authenticated;

create table benchmark_private.oi_audit (
  id bigint generated always as identity primary key,
  actor_id uuid not null,
  action text not null,
  target_id uuid not null,
  created_at timestamptz not null default now()
);
alter table benchmark_private.oi_audit enable row level security;
revoke all on benchmark_private.oi_audit from public,anon,authenticated;

create function benchmark_private.oi_mutate(action text, payload jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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
begin
  if actor is null then raise exception 'Sign in required' using errcode='42501'; end if;
  if payload is null or jsonb_typeof(payload)<>'object' then raise exception 'Invalid payload' using errcode='22023'; end if;
  target := (payload->>'id')::uuid;
  if target is null then raise exception 'ID required' using errcode='22023'; end if;

  if action='start_evidence' then
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
    insert into public.oi_stories(id,user_id,grant_id,region_id,title,body,theme,emotion,cucumber_name,cucumber_asset,card_asset,latitude,longitude)
      values(target,actor,permission.id,payload->>'region_id',payload->>'title',payload->>'body',payload->>'theme',payload->>'emotion',
        payload->>'cucumber_name',payload->>'cucumber_asset',payload->>'card_asset',(payload->>'latitude')::double precision,(payload->>'longitude')::double precision)
      on conflict(id) do update set title=excluded.title,body=excluded.body,theme=excluded.theme,emotion=excluded.emotion,
        region_id=excluded.region_id,cucumber_name=excluded.cucumber_name,cucumber_asset=excluded.cucumber_asset,
        card_asset=excluded.card_asset,latitude=excluded.latitude,longitude=excluded.longitude,
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
$$;
revoke all on function benchmark_private.oi_mutate(text,jsonb) from public,anon;
grant execute on function benchmark_private.oi_mutate(text,jsonb) to authenticated;

create function public.oi_mutate(p_action text,p_payload jsonb) returns jsonb
language sql security invoker set search_path = '' as $$
  select benchmark_private.oi_mutate(p_action,p_payload);
$$;
revoke all on function public.oi_mutate(text,jsonb) from public,anon;
grant execute on function public.oi_mutate(text,jsonb) to authenticated;

commit;
