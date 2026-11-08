begin;

-- Match the already-deployed campus schema when starting from repository migrations.
alter table public.oi_stories
  add column if not exists height_meters double precision not null default 1.0,
  add column if not exists heading_degrees double precision not null default 0.0;

do $patch$
declare
  definition text := pg_get_functiondef('benchmark_private.oi_mutate(text,jsonb)'::regprocedure);
  change record;
begin
  if position('height_meters=excluded.height_meters,heading_degrees=excluded.heading_degrees' in definition)>0 then
    return;
  end if;
  for change in
    select * from (values
      ('cucumber_asset,card_asset,latitude,longitude)',
       'cucumber_asset,card_asset,latitude,longitude,height_meters,heading_degrees)'),
      ($old$(payload->>'longitude')::double precision)
      on conflict(id) do update$old$,
       $new$(payload->>'longitude')::double precision,
        coalesce((payload->>'height_meters')::double precision,story.height_meters,1.0),
        coalesce((payload->>'heading_degrees')::double precision,story.heading_degrees,0.0))
      on conflict(id) do update$new$),
      ('card_asset=excluded.card_asset,latitude=excluded.latitude,longitude=excluded.longitude,',
       'card_asset=excluded.card_asset,latitude=excluded.latitude,longitude=excluded.longitude,
        height_meters=excluded.height_meters,heading_degrees=excluded.heading_degrees,')
    ) as changes(before_text, after_text)
  loop
    if length(definition)-length(replace(definition,change.before_text,''))<>length(change.before_text) then
      raise exception 'oi_mutate drift requires review before adding story placement geometry';
    end if;
    definition := replace(definition,change.before_text,change.after_text);
  end loop;
  execute definition;
end; $patch$;

notify pgrst,'reload schema';
commit;
