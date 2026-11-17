create or replace function benchmark_private.oi_check_cucumber_appearance(story public.oi_stories, appearance jsonb)
returns void language plpgsql set search_path='' as $$
declare
  field text;
  seed jsonb;
  shape jsonb;
  face jsonb;
  garment text;
  numeric_value numeric;
  slot_count integer;
  garment_count integer;
begin
  if jsonb_typeof(appearance) is distinct from 'object' or pg_column_size(appearance)>2048 then
    raise exception 'Invalid cucumber appearance' using errcode='22023';
  end if;
  if appearance ? 'seed' then
    seed := appearance->'seed';
    shape := seed->'appearance';
    if jsonb_typeof(seed) is distinct from 'object' or seed-array['appearance','garments']<>'{}'::jsonb
      or jsonb_typeof(shape) is distinct from 'object'
      or shape-array['eyes','mouth','eyeSpacing','stemLength','stemAngle','bodyHeight','bodyWidth']<>'{}'::jsonb
      or jsonb_typeof(seed->'garments') is distinct from 'array'
      or appearance->'topTexture' is distinct from 'false'::jsonb
      or appearance->'bottomTexture' is distinct from 'false'::jsonb then
      raise exception 'Invalid seed cucumber appearance' using errcode='22023';
    end if;
    for field, face in select key,value from jsonb_each(shape) where key in ('eyes','mouth') loop
      if jsonb_typeof(face) is distinct from 'object' or face-array['x','y','size']<>'{}'::jsonb
        or jsonb_typeof(face->'x') is distinct from 'number'
        or jsonb_typeof(face->'y') is distinct from 'number'
        or jsonb_typeof(face->'size') is distinct from 'number' then
        raise exception 'Invalid seed cucumber face' using errcode='22023';
      end if;
      if (face->>'x')::numeric not between -80 and 80
        or (face->>'y')::numeric not between -110 and 140
        or (face->>'size')::numeric not between 0.5 and 2 then
        raise exception 'Invalid seed cucumber face' using errcode='22023';
      end if;
    end loop;
    if not (shape ?& array['eyes','mouth']) then
      raise exception 'Invalid seed cucumber face' using errcode='22023';
    end if;
    foreach field in array array['eyeSpacing','stemLength','stemAngle','bodyHeight','bodyWidth'] loop
      if jsonb_typeof(shape->field) is distinct from 'number' then
        raise exception 'Invalid seed cucumber shape' using errcode='22023';
      end if;
      numeric_value := (shape->>field)::numeric;
      if not (case field
        when 'eyeSpacing' then numeric_value between 0.70 and 1.30
        when 'stemLength' then numeric_value between 0.5 and 1.65
        when 'stemAngle' then numeric_value between -130 and 35
        when 'bodyHeight' then numeric_value between 0.85 and 1.20
        when 'bodyWidth' then numeric_value between 0.90 and 1.30
      end) then
        raise exception 'Invalid seed cucumber shape' using errcode='22023';
      end if;
    end loop;

    garment_count := jsonb_array_length(seed->'garments');
    if garment_count > 3 then raise exception 'Invalid seed cucumber outfit' using errcode='22023'; end if;
    for garment in select jsonb_array_elements_text(seed->'garments') loop
      if garment is null or garment not in (
      'seed-costume-astronaut',
      'seed-costume-astronaut-navy',
      'seed-costume-astronaut-navy-proposal-1',
      'seed-costume-astronaut-navy-proposal-2',
      'seed-costume-astronaut-navy-proposal-3',
      'seed-costume-astronaut-proposal-1',
      'seed-costume-astronaut-proposal-2',
      'seed-costume-astronaut-proposal-3',
      'seed-costume-baseball',
      'seed-costume-bee',
      'seed-costume-cat',
      'seed-costume-cat-bear',
      'seed-costume-cat-bear-proposal-1',
      'seed-costume-cat-bear-proposal-2',
      'seed-costume-cat-bear-proposal-3',
      'seed-costume-cowboy',
      'seed-costume-dinosaur',
      'seed-costume-farmer',
      'seed-costume-martial-arts',
      'seed-costume-postech-selfie',
      'seed-costume-postech-selfie-proposal-1',
      'seed-costume-raincoat',
      'seed-costume-raincoat-proposal-1',
      'seed-costume-school-uniform',
      'seed-costume-school-uniform-trousers',
      'seed-costume-scientist',
      'seed-costume-scientist-goggles',
      'seed-costume-scientist-proposal-1',
      'seed-costume-scientist-proposal-2',
      'seed-costume-scientist-proposal-3',
      'seed-costume-sportswear',
      'SeedCucumberWhiteTshirt',
      'SeedCucumberHoodie',
      'SeedCucumberCardigan',
      'SeedCucumberPostechJacket',
      'SeedCucumberLongPants',
      'SeedCucumberShorts',
      'SeedCucumberSneakers'
      ) then
        raise exception 'Invalid seed cucumber outfit' using errcode='22023';
      end if;
    end loop;
    select count(distinct case
      when item like 'seed-costume-%' then 'costume'
      when item in ('SeedCucumberLongPants','SeedCucumberShorts') then 'bottom'
      when item = 'SeedCucumberSneakers' then 'shoes'
      else 'top' end
    ) into slot_count from jsonb_array_elements_text(seed->'garments') item;
    if slot_count <> garment_count or (garment_count > 1 and exists (
      select 1 from jsonb_array_elements_text(seed->'garments') item where item like 'seed-costume-%'
    )) then
      raise exception 'Invalid seed cucumber outfit' using errcode='22023';
    end if;
    appearance := appearance - 'seed';
  end if;

  if pg_column_size(appearance)>1024 then
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
