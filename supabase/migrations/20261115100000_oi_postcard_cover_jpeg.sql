begin;

-- The format number and all existing PNG paths remain unchanged. Only format 3
-- has a cover; old snapshots explicitly retain their original PNG encoding.
alter table public.oi_stories add column card_cover_type text;
update public.oi_stories set card_cover_type='png' where card_snapshot_format=3;
alter table public.oi_stories add constraint oi_story_card_cover_type_check check (
  (card_snapshot_format in (1,2) and card_cover_type is null)
  or (card_snapshot_format=3 and card_cover_type is not null and card_cover_type in ('png','jpeg'))
);

-- Keep the four-argument helper and its grants intact for legacy callers.
-- Not STRICT: formats 1/2 legitimately pass NULL for the absent cover type.
create function benchmark_private.oi_story_card_parts(
  owner_id uuid,story_id uuid,snapshot_id uuid,format integer,cover_type text
) returns text[] language sql immutable set search_path='' as $$
  select case
    when (format in (1,2) and cover_type is null) or (format=3 and cover_type='png') then
      benchmark_private.oi_story_card_parts(owner_id,story_id,snapshot_id,format)
    when format=3 and cover_type='jpeg' then
      benchmark_private.oi_story_card_parts(owner_id,story_id,snapshot_id,2) || array[
        owner_id::text||'/'||story_id::text||'/card/'||snapshot_id::text||'/cover.jpg'
      ]
    else null::text[]
  end;
$$;
revoke all on function benchmark_private.oi_story_card_parts(uuid,uuid,uuid,integer,text) from public;
grant execute on function benchmark_private.oi_story_card_parts(uuid,uuid,uuid,integer,text) to anon,authenticated;

alter policy oi_duplex_story_card_read on storage.objects using (
  bucket_id='oi-story-media' and (storage.foldername(name))[3]='card' and exists (
    select 1 from public.oi_stories s
    where s.id::text=(storage.foldername(name))[2] and s.card_snapshot_format in (2,3)
      and (s.status='published' or (s.status<>'deleted' and s.user_id=(select benchmark_private.oi_account_id())))
      and name=any(benchmark_private.oi_story_card_parts(s.storage_owner_id,s.id,s.card_snapshot_id,s.card_snapshot_format,s.card_cover_type))
  )
);

-- Patch the deployed validator rather than replacing any other checks it owns.
-- PNG parts (including old covers) remain 8MiB; only cover.jpg is JPEG/2MiB.
do $validation$
declare definition text := pg_get_functiondef('benchmark_private.oi_check_story_card(public.oi_stories)'::regprocedure); change record;
begin
  for change in select * from (values
    ($old$foreach path in array benchmark_private.oi_story_card_parts(story.storage_owner_id,story.id,story.card_snapshot_id,story.card_snapshot_format) loop$old$,
     $new$if story.card_snapshot_id is null
    or benchmark_private.oi_story_card_parts(story.storage_owner_id,story.id,story.card_snapshot_id,story.card_snapshot_format,story.card_cover_type) is null then
    raise exception 'Invalid card artwork declaration' using errcode='22023';
  end if;
  foreach path in array benchmark_private.oi_story_card_parts(story.storage_owner_id,story.id,story.card_snapshot_id,story.card_snapshot_format,story.card_cover_type) loop$new$),
    ($old$and o.metadata->>'mimetype'='image/png'$old$,
     $new$and o.metadata->>'mimetype'=case when story.card_cover_type='jpeg'
          and path=story.storage_owner_id::text||'/'||story.id::text||'/card/'||story.card_snapshot_id::text||'/cover.jpg'
          then 'image/jpeg' else 'image/png' end$new$),
    ($old$between 1 and 8388608$old$,
     $new$between 1 and case when story.card_cover_type='jpeg'
          and path=story.storage_owner_id::text||'/'||story.id::text||'/card/'||story.card_snapshot_id::text||'/cover.jpg'
          then 2097152 else 8388608 end$new$)
  ) as changes(before_text,after_text) loop
    if length(definition)-length(replace(definition,change.before_text,''))<>length(change.before_text) then
      raise exception 'oi_check_story_card drift requires JPEG cover review: %',change.before_text;
    end if;
    definition := replace(definition,change.before_text,change.after_text);
  end loop;
  execute definition;
end; $validation$;

do $patch$
declare definition text := pg_get_functiondef('benchmark_private.oi_mutate(text,jsonb)'::regprocedure); change record;
begin
  for change in select * from (values
    ($old$      if payload ? 'card_snapshot_id' then
        story.card_snapshot_id := (payload->>'card_snapshot_id')::uuid;
        story.card_snapshot_format := coalesce((payload->>'card_snapshot_format')::integer,1);
        if story.card_snapshot_format not in (1,2,3) then
          raise exception 'Invalid card format' using errcode='22023';
        end if;
      end if;$old$,
     $new$      if payload ? 'card_snapshot_id' then
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
      end if;$new$),
    ($old$    if action='review_story' and wanted_status='published' and story.card_snapshot_id is not null then$old$,
     $new$    if action='review_story' and wanted_status='published' and story.card_snapshot_id is not null then
      if (story.card_cover_type='jpeg' and
          (jsonb_typeof(payload->'card_cover_type') is distinct from 'string'
            or payload->>'card_cover_type' is distinct from story.card_cover_type))
        or (payload ? 'card_cover_type' and payload->>'card_cover_type' is distinct from story.card_cover_type) then
        raise exception 'Review the current cover with an updated operator app' using errcode='40001';
      end if;$new$),
    ($old$card_snapshot_id=story.card_snapshot_id,card_snapshot_format=story.card_snapshot_format,$old$,
     $new$card_snapshot_id=story.card_snapshot_id,card_snapshot_format=story.card_snapshot_format,card_cover_type=story.card_cover_type,$new$)
  ) as changes(before_text,after_text) loop
    if length(definition)-length(replace(definition,change.before_text,''))<>length(change.before_text) then
      raise exception 'oi_mutate drift requires JPEG cover review: %',change.before_text;
    end if;
    definition := replace(definition,change.before_text,change.after_text);
  end loop;
  execute definition;
end; $patch$;

do $capability$
declare definition text := pg_get_functiondef('public.oi_capabilities()'::regprocedure);
  anchor constant text := '''story_card_cover'',true';
begin
  if length(definition)-length(replace(definition,anchor,''))<>length(anchor) then
    raise exception 'oi_capabilities drift requires JPEG cover review';
  end if;
  execute replace(definition,anchor,'''story_card_cover_jpeg'',true,'||anchor);
end; $capability$;

notify pgrst,'reload schema';
commit;
