begin;

-- Format 3 adds a sticker-free cover to the same reviewed, immutable bundle.
-- Existing single-sided and duplex snapshots keep their paths and defaults.
alter table public.oi_stories drop constraint oi_stories_card_snapshot_format_check;
alter table public.oi_stories add constraint oi_stories_card_snapshot_format_check
  check (card_snapshot_format in (1,2,3));
alter table public.oi_stories drop constraint oi_duplex_card_requires_snapshot;
alter table public.oi_stories add constraint oi_duplex_card_requires_snapshot
  check (card_snapshot_format=1 or (card_snapshot_format in (2,3) and card_snapshot_id is not null));

create or replace function benchmark_private.oi_story_card_parts(owner_id uuid,story_id uuid,snapshot_id uuid,format integer)
returns text[] language sql immutable strict set search_path='' as $$
  select case when format in (2,3) then array[
    benchmark_private.oi_story_card_path(owner_id,story_id,snapshot_id),
    owner_id::text||'/'||story_id::text||'/card/'||snapshot_id::text||'/back.png',
    owner_id::text||'/'||story_id::text||'/card/'||snapshot_id::text||'/front-preview.png',
    owner_id::text||'/'||story_id::text||'/card/'||snapshot_id::text||'/back-preview.png'
  ] || case when format=3 then array[
    owner_id::text||'/'||story_id::text||'/card/'||snapshot_id::text||'/cover.png'
  ] else array[]::text[] end
  else array[benchmark_private.oi_story_card_path(owner_id,story_id,snapshot_id)] end;
$$;

alter policy oi_duplex_story_card_read on storage.objects using (
  bucket_id='oi-story-media' and (storage.foldername(name))[3]='card' and exists (
    select 1 from public.oi_stories s
    where s.id::text=(storage.foldername(name))[2] and s.card_snapshot_format in (2,3)
      and (s.status='published' or (s.status<>'deleted' and s.user_id=(select benchmark_private.oi_account_id())))
      and name=any(benchmark_private.oi_story_card_parts(s.storage_owner_id,s.id,s.card_snapshot_id,s.card_snapshot_format))
  )
);

-- oi_check_story_card already iterates oi_story_card_parts: the fifth PNG must
-- also exist with image/png metadata and a size of 1..8388608 bytes at submission
-- and approval. Keep that shared validator and its permissions unchanged.
do $patch$
declare definition text := pg_get_functiondef('benchmark_private.oi_mutate(text,jsonb)'::regprocedure); change record;
begin
  for change in select * from (values
    ($old$if story.card_snapshot_format not in (1,2) then$old$,
     $new$if story.card_snapshot_format not in (1,2,3) then$new$),
    ($old$(story.card_snapshot_format=2 and coalesce(payload->>'card_snapshot_format','')<>'2')$old$,
     $new$(story.card_snapshot_format>=2 and coalesce(payload->>'card_snapshot_format','')<>story.card_snapshot_format::text)$new$)
  ) as changes(before_text,after_text) loop
    if length(definition)-length(replace(definition,change.before_text,''))<>length(change.before_text) then
      raise exception 'oi_mutate drift requires postcard cover review: %',change.before_text;
    end if;
    definition := replace(definition,change.before_text,change.after_text);
  end loop;
  execute definition;
end; $patch$;

do $capability$
declare definition text := pg_get_functiondef('public.oi_capabilities()'::regprocedure);
  anchor constant text := '''duplex_story_card'',true';
begin
  if length(definition)-length(replace(definition,anchor,''))<>length(anchor) then
    raise exception 'oi_capabilities drift requires postcard cover review';
  end if;
  execute replace(definition,anchor,'''story_card_cover'',true,'||anchor);
end; $capability$;

notify pgrst,'reload schema';
commit;
