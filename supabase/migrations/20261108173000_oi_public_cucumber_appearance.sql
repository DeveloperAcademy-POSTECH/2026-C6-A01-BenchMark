begin;

-- The row holds only the approved model options and a reference to immutable rendered images.
alter table public.oi_stories add column cucumber_appearance jsonb;

create function benchmark_private.oi_cucumber_appearance_paths(owner_id uuid, story_id uuid, appearance jsonb)
returns text[] language sql immutable set search_path='' as $$
  select array_remove(array[
    base||'portrait.png',
    case when appearance->'topTexture'='true'::jsonb then base||'top.png' end,
    case when appearance->'bottomTexture'='true'::jsonb then base||'bottom.png' end
  ],null)
  from (select owner_id::text||'/'||story_id::text||'/appearance/'||(appearance->>'id')||'/' as base) p;
$$;
revoke all on function benchmark_private.oi_cucumber_appearance_paths(uuid,uuid,jsonb) from public;
grant execute on function benchmark_private.oi_cucumber_appearance_paths(uuid,uuid,jsonb) to anon,authenticated;

create function benchmark_private.oi_check_cucumber_appearance(story public.oi_stories, appearance jsonb)
returns void language plpgsql set search_path='' as $$
declare field text;
begin
  if jsonb_typeof(appearance) is distinct from 'object' or pg_column_size(appearance)>1024 then
    raise exception 'Invalid cucumber appearance' using errcode='22023';
  end if;
  if appearance-array['id','top','bottom','costume','topColor','bottomColor','shoeColor','topTexture','bottomTexture']<>'{}'::jsonb
    or coalesce(appearance->>'id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or coalesce(appearance->>'top','') not in ('tshirt','hoodie','cardigan','postech')
    or coalesce(appearance->>'bottom','') not in ('long','shorts')
    or jsonb_typeof(appearance->'topTexture') is distinct from 'boolean'
    or jsonb_typeof(appearance->'bottomTexture') is distinct from 'boolean'
    or (appearance ? 'costume' and (
      coalesce(appearance->>'costume','') not in ('dinosaur','raincoat','bee','cat','astronaut','scientist','cat-bear',
        'postech-selfie','baseball','cowboy','farmer','sportswear','martial-arts','school-uniform',
        'school-uniform-trousers','astronaut-navy','scientist-goggles') or appearance->'bottomTexture'='true'::jsonb)) then
    raise exception 'Invalid cucumber appearance' using errcode='22023';
  end if;
  foreach field in array array['topColor','bottomColor','shoeColor'] loop
    if jsonb_typeof(appearance->field) is distinct from 'number' or (appearance->>field) !~ '^[0-9]{1,8}$' then
      raise exception 'Invalid cucumber color' using errcode='22023';
    end if;
    if (appearance->>field)::integer>16777215 then
      raise exception 'Invalid cucumber color' using errcode='22023';
    end if;
  end loop;
  if exists (
    select 1 from unnest(benchmark_private.oi_cucumber_appearance_paths(story.storage_owner_id,story.id,appearance)) path
    where not exists(select 1 from storage.objects o where o.bucket_id='oi-story-media' and o.name=path
      and o.metadata->>'mimetype'='image/png'
      and case when o.metadata->>'size' ~ '^[0-9]{1,8}$' then (o.metadata->>'size')::integer between 1 and 8388608 else false end)
  ) then
    raise exception 'Cucumber artwork is missing' using errcode='22023';
  end if;
end;
$$;
revoke all on function benchmark_private.oi_check_cucumber_appearance(public.oi_stories,jsonb) from public,anon,authenticated;

-- Existing upload policies still require the owning account, a draft, and open writing.
-- Public reads can see exactly the images attached to the currently published snapshot.
create policy oi_cucumber_appearance_read on storage.objects for select to anon,authenticated using (
  bucket_id='oi-story-media' and (storage.foldername(name))[3]='appearance' and exists (
    select 1 from public.oi_stories s
    where s.id::text=(storage.foldername(name))[2] and s.status='published' and s.cucumber_appearance is not null
      and name=any(benchmark_private.oi_cucumber_appearance_paths(s.storage_owner_id,s.id,s.cucumber_appearance))
  )
);

-- Authors can preview an already submitted outfit; operators already have story-media read access.
create policy oi_cucumber_appearance_owner_read on storage.objects for select to authenticated using (
  bucket_id='oi-story-media' and (storage.foldername(name))[3]='appearance' and exists (
    select 1 from public.oi_stories s
    where s.id::text=(storage.foldername(name))[2] and s.status<>'deleted' and s.cucumber_appearance is not null
      and s.user_id=(select benchmark_private.oi_account_id())
      and name=any(benchmark_private.oi_cucumber_appearance_paths(s.storage_owner_id,s.id,s.cucumber_appearance))
  )
);

-- Keep the current ownership, pause, and revision checks in the single story transaction.
do $patch$
declare
  definition text := pg_get_functiondef('benchmark_private.oi_mutate(text,jsonb)'::regprocedure);
  change record;
begin
  for change in select * from (values
    ($old$if not starts_with(path,story.storage_owner_id::text||'/'||target::text||'/')$old$,
     $new$if (storage.foldername(path))[3]='appearance' or not starts_with(path,story.storage_owner_id::text||'/'||target::text||'/')$new$),
    ($old$      wanted_status := 'pending';
    elsif action='reopen_story' then$old$,
     $new$      if payload ? 'cucumber_appearance' then
        perform benchmark_private.oi_check_cucumber_appearance(story,payload->'cucumber_appearance');
        story.cucumber_appearance := payload->'cucumber_appearance';
      end if;
      wanted_status := 'pending';
    elsif action='reopen_story' then$new$),
    ($old$    update public.oi_stories set status=wanted_status,revision=revision+1,updated_at=now() where id=target returning * into story;$old$,
     $new$    if action='review_story' and wanted_status='published' and story.cucumber_appearance is not null then
      if payload->>'appearance_id' is distinct from story.cucumber_appearance->>'id' then
        raise exception 'Review the current cucumber appearance first' using errcode='40001';
      end if;
      perform benchmark_private.oi_check_cucumber_appearance(story,story.cucumber_appearance);
    end if;
    update public.oi_stories set status=wanted_status,cucumber_appearance=story.cucumber_appearance,
      revision=revision+1,updated_at=now() where id=target returning * into story;$new$)
  ) as changes(before_text,after_text) loop
    if length(definition)-length(replace(definition,change.before_text,''))<>length(change.before_text) then
      raise exception 'oi_mutate drift requires review before cucumber appearance: %',left(btrim(change.before_text),96);
    end if;
    definition := replace(definition,change.before_text,change.after_text);
  end loop;
  execute definition;
end; $patch$;

do $capability$
declare
  definition text := pg_get_functiondef('public.oi_capabilities()'::regprocedure);
  anchor constant text := '''independent_story_creation'',true';
begin
  if length(definition)-length(replace(definition,anchor,''))<>length(anchor) then
    raise exception 'oi_capabilities drift requires review before cucumber appearance';
  end if;
  execute replace(definition,anchor,'''public_cucumber_appearance'',true,'||anchor);
end; $capability$;

notify pgrst,'reload schema';
commit;
