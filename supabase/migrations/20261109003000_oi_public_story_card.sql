begin;

-- This is the authored card flattened for review. Older stories retain their existing artwork.
alter table public.oi_stories add column card_snapshot_id uuid;

create function benchmark_private.oi_story_card_path(owner_id uuid, story_id uuid, snapshot_id uuid)
returns text language sql immutable strict set search_path='' as $$
  select owner_id::text||'/'||story_id::text||'/card/'||snapshot_id::text||'.png';
$$;
revoke all on function benchmark_private.oi_story_card_path(uuid,uuid,uuid) from public;
grant execute on function benchmark_private.oi_story_card_path(uuid,uuid,uuid) to anon,authenticated;

create policy oi_story_card_read on storage.objects for select to anon,authenticated using (
  bucket_id='oi-story-media' and (storage.foldername(name))[3]='card' and exists (
    select 1 from public.oi_stories s
    where s.id::text=(storage.foldername(name))[2]
      and (s.status='published' or (s.status<>'deleted' and s.user_id=(select benchmark_private.oi_account_id())))
      and name=benchmark_private.oi_story_card_path(s.storage_owner_id,s.id,s.card_snapshot_id)
  )
);

create function benchmark_private.oi_check_story_card(story public.oi_stories)
returns void language plpgsql set search_path='' as $$
begin
  if not exists (
    select 1 from storage.objects o where o.bucket_id='oi-story-media'
      and o.name=benchmark_private.oi_story_card_path(story.storage_owner_id,story.id,story.card_snapshot_id)
      and o.metadata->>'mimetype'='image/png'
      and case when o.metadata->>'size' ~ '^[0-9]{1,8}$' then (o.metadata->>'size')::integer between 1 and 8388608 else false end
  ) then
    raise exception 'Card artwork is missing' using errcode='22023';
  end if;
end;
$$;
revoke all on function benchmark_private.oi_check_story_card(public.oi_stories) from public,anon,authenticated;

-- Reuse the story transaction so content and the reviewed card share the same revision.
do $patch$
declare
  definition text := pg_get_functiondef('benchmark_private.oi_mutate(text,jsonb)'::regprocedure);
  change record;
begin
  for change in select * from (values
    ($old$(storage.foldername(path))[3]='appearance'$old$,
     $new$(storage.foldername(path))[3] in ('appearance','card')$new$),
    ($old$      wanted_status := 'pending';
    elsif action='reopen_story' then$old$,
     $new$      if payload ? 'card_snapshot_id' then
        story.card_snapshot_id := (payload->>'card_snapshot_id')::uuid;
      end if;
      if story.card_snapshot_id is not null or payload ? 'card_snapshot_id' then
        perform benchmark_private.oi_check_story_card(story);
      end if;
      wanted_status := 'pending';
    elsif action='reopen_story' then$new$),
    ($old$    update public.oi_stories set status=wanted_status,cucumber_appearance=story.cucumber_appearance,$old$,
     $new$    if action='review_story' and wanted_status='published' and story.card_snapshot_id is not null then
      if payload->>'card_snapshot_id' is distinct from story.card_snapshot_id::text then
        raise exception 'Review the current story card first' using errcode='40001';
      end if;
      perform benchmark_private.oi_check_story_card(story);
    end if;
    update public.oi_stories set status=wanted_status,cucumber_appearance=story.cucumber_appearance,
      card_snapshot_id=story.card_snapshot_id,$new$)
  ) as changes(before_text,after_text) loop
    if length(definition)-length(replace(definition,change.before_text,''))<>length(change.before_text) then
      raise exception 'oi_mutate drift requires review before story card: %',left(btrim(change.before_text),96);
    end if;
    definition := replace(definition,change.before_text,change.after_text);
  end loop;
  execute definition;
end; $patch$;

do $capability$
declare
  definition text := pg_get_functiondef('public.oi_capabilities()'::regprocedure);
  anchor constant text := '''public_cucumber_appearance'',true';
begin
  if length(definition)-length(replace(definition,anchor,''))<>length(anchor) then
    raise exception 'oi_capabilities drift requires review before story card';
  end if;
  execute replace(definition,anchor,'''public_story_card'',true,'||anchor);
end; $capability$;

notify pgrst,'reload schema';
commit;
