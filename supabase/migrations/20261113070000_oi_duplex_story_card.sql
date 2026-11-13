begin;

-- Format 1 remains the existing single PNG. Format 2 binds four immutable files
-- to the existing content-derived snapshot UUID; the legacy front path stays valid.
alter table public.oi_stories add column card_snapshot_format integer not null default 1
  check (card_snapshot_format in (1,2));
alter table public.oi_stories add constraint oi_duplex_card_requires_snapshot
  check (card_snapshot_format=1 or card_snapshot_id is not null);

create function benchmark_private.oi_story_card_parts(owner_id uuid,story_id uuid,snapshot_id uuid,format integer)
returns text[] language sql immutable strict set search_path='' as $$
  select case when format=2 then array[
    benchmark_private.oi_story_card_path(owner_id,story_id,snapshot_id),
    owner_id::text||'/'||story_id::text||'/card/'||snapshot_id::text||'/back.png',
    owner_id::text||'/'||story_id::text||'/card/'||snapshot_id::text||'/front-preview.png',
    owner_id::text||'/'||story_id::text||'/card/'||snapshot_id::text||'/back-preview.png'
  ] else array[benchmark_private.oi_story_card_path(owner_id,story_id,snapshot_id)] end;
$$;
revoke all on function benchmark_private.oi_story_card_parts(uuid,uuid,uuid,integer) from public;
grant execute on function benchmark_private.oi_story_card_parts(uuid,uuid,uuid,integer) to anon,authenticated;

create policy oi_duplex_story_card_read on storage.objects for select to anon,authenticated using (
  bucket_id='oi-story-media' and (storage.foldername(name))[3]='card' and exists (
    select 1 from public.oi_stories s
    where s.id::text=(storage.foldername(name))[2] and s.card_snapshot_format=2
      and (s.status='published' or (s.status<>'deleted' and s.user_id=(select benchmark_private.oi_account_id())))
      and name=any(benchmark_private.oi_story_card_parts(s.storage_owner_id,s.id,s.card_snapshot_id,2))
  )
);

create or replace function benchmark_private.oi_check_story_card(story public.oi_stories)
returns void language plpgsql set search_path='' as $$
declare path text;
begin
  foreach path in array benchmark_private.oi_story_card_parts(story.storage_owner_id,story.id,story.card_snapshot_id,story.card_snapshot_format) loop
    if not exists (
      select 1 from storage.objects o where o.bucket_id='oi-story-media' and o.name=path
        and o.metadata->>'mimetype'='image/png'
        and case when o.metadata->>'size' ~ '^[0-9]{1,8}$' then (o.metadata->>'size')::integer between 1 and 8388608 else false end
    ) then
      raise exception 'Card artwork is missing or invalid' using errcode='22023';
    end if;
  end loop;
end; $$;

do $patch$
declare definition text := pg_get_functiondef('benchmark_private.oi_mutate(text,jsonb)'::regprocedure); change record;
begin
  for change in select * from (values
    ($old$story.card_snapshot_id := (payload->>'card_snapshot_id')::uuid;$old$,
     $new$story.card_snapshot_id := (payload->>'card_snapshot_id')::uuid;
        story.card_snapshot_format := coalesce((payload->>'card_snapshot_format')::integer,1);
        if story.card_snapshot_format not in (1,2) then
          raise exception 'Invalid card format' using errcode='22023';
        end if;$new$),
    ($old$if payload->>'card_snapshot_id' is distinct from story.card_snapshot_id::text then$old$,
     $new$if payload->>'card_snapshot_id' is distinct from story.card_snapshot_id::text
        or (story.card_snapshot_format=2 and coalesce(payload->>'card_snapshot_format','')<>'2') then$new$),
    ($old$card_snapshot_id=story.card_snapshot_id,$old$,
     $new$card_snapshot_id=story.card_snapshot_id,card_snapshot_format=story.card_snapshot_format,$new$)
  ) as changes(before_text,after_text) loop
    if length(definition)-length(replace(definition,change.before_text,''))<>length(change.before_text) then
      raise exception 'oi_mutate drift requires duplex card review: %',change.before_text;
    end if;
    definition := replace(definition,change.before_text,change.after_text);
  end loop;
  execute definition;
end; $patch$;

do $capability$
declare definition text := pg_get_functiondef('public.oi_capabilities()'::regprocedure);
  anchor constant text := '''public_story_card'',true';
begin
  if length(definition)-length(replace(definition,anchor,''))<>length(anchor) then
    raise exception 'oi_capabilities drift requires duplex card review';
  end if;
  execute replace(definition,anchor,'''duplex_story_card'',true,'||anchor);
end; $capability$;

notify pgrst,'reload schema';
commit;
