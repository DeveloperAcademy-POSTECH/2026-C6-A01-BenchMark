\set ON_ERROR_STOP on
begin;

create function pg_temp.check_result(value boolean, message text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception '%',message; end if; end;
$$;

create function pg_temp.action(action text, revision integer, fields jsonb default '{}') returns jsonb language sql as $$
  select public.oi_mutate(action,jsonb_build_object('id','c2400000-0000-4000-8000-000000000011','revision',revision)||fields);
$$;

create function pg_temp.look() returns jsonb language sql as $$
  select '{"id":"c2400000-0000-4000-8000-000000000021","top":"hoodie","bottom":"shorts",
    "topColor":16711680,"bottomColor":255,"shoeColor":65280,"topTexture":true,"bottomTexture":false}'::jsonb;
$$;

insert into auth.users(id) values
  ('c2400000-0000-4000-8000-000000000001'),('c2400000-0000-4000-8000-000000000002'),('c2400000-0000-4000-8000-000000000003');
insert into benchmark_private.oi_operators values('c2400000-0000-4000-8000-000000000003');

set local role authenticated;
select set_config('request.jwt.claim.sub','c2400000-0000-4000-8000-000000000001',true);
select pg_temp.check_result(public.oi_capabilities()->>'public_cucumber_appearance'='true','appearance capability is present');
select pg_temp.check_result(public.oi_capabilities()->>'public_story_card'='true','card capability is present');
select pg_temp.action('save_story',0,'{"region_id":"pond","title":"Synthetic outfit","body":"Synthetic draft","theme":"감사","emotion":"기쁨",
  "cucumber_name":"테스트오이","cucumber_asset":"OiCats","card_asset":"MYBasicCard",
  "latitude":36.01261057,"longitude":129.31972687,"height_meters":1.2,"heading_degrees":42}');

-- Unattached versions, unreferenced files, and files from a different story must stay private.
insert into storage.objects(bucket_id,name,metadata) values
 ('oi-story-media','c2400000-0000-4000-8000-000000000001/c2400000-0000-4000-8000-000000000011/appearance/c2400000-0000-4000-8000-000000000021/portrait.png','{"mimetype":"image/png","size":1024}'),
 ('oi-story-media','c2400000-0000-4000-8000-000000000001/c2400000-0000-4000-8000-000000000011/appearance/c2400000-0000-4000-8000-000000000021/bottom.png','{"mimetype":"image/png","size":1024}'),
 ('oi-story-media','c2400000-0000-4000-8000-000000000001/c2400000-0000-4000-8000-000000000011/appearance/c2400000-0000-4000-8000-000000000022/portrait.png','{"mimetype":"image/png","size":1024}');

reset role;
do $$
declare
  story public.oi_stories;
  appearance jsonb := pg_temp.look() || '{
    "topTexture":false,
    "seed":{"appearance":{"eyes":{"x":0,"y":0,"size":1},"mouth":{"x":0,"y":0,"size":1},
      "eyeSpacing":1,"stemLength":1,"stemAngle":0,"bodyHeight":1.2,"bodyWidth":1},
      "garments":["seed-costume-raincoat-proposal-1"]}}'::jsonb;
begin
  select * into strict story from public.oi_stories where id = 'c2400000-0000-4000-8000-000000000011';
  perform benchmark_private.oi_check_cucumber_appearance(story, appearance);
  begin
    perform benchmark_private.oi_check_cucumber_appearance(story, jsonb_set(appearance, '{seed,appearance,bodyHeight}', '1000'));
    raise exception 'out-of-range body height was accepted';
  exception when invalid_parameter_value then null; end;
  begin
    perform benchmark_private.oi_check_cucumber_appearance(story, jsonb_set(appearance, '{seed,garments}', '["SeedCucumberHoodie","SeedCucumberCardigan"]'));
    raise exception 'two top garments were accepted';
  exception when invalid_parameter_value then null; end;
  begin
    perform benchmark_private.oi_check_cucumber_appearance(story, jsonb_set(appearance, '{seed,garments}', '["not-an-outfit"]'));
    raise exception 'unbundled garment was accepted';
  exception when invalid_parameter_value then null; end;
end;
$$;

-- A seed photo is a reviewed garment atlas, never embedded original sources.
insert into storage.objects(bucket_id,name,metadata) values
 ('oi-story-media','c2400000-0000-4000-8000-000000000001/c2400000-0000-4000-8000-000000000011/appearance/c2400000-0000-4000-8000-000000000021/top.png','{"mimetype":"image/png","size":1024}');

create function pg_temp.reject_seed_photo(story public.oi_stories, appearance jsonb, message text)
returns void language plpgsql as $$
begin
  perform benchmark_private.oi_check_cucumber_appearance(story,appearance);
  raise exception '%',message;
exception when invalid_parameter_value then null;
end;
$$;

do $$
declare
  story public.oi_stories;
  appearance jsonb := pg_temp.look() || '{
    "seed":{"appearance":{"eyes":{"x":0,"y":0,"size":1},"mouth":{"x":0,"y":0,"size":1},
      "eyeSpacing":1,"stemLength":1,"stemAngle":0,"bodyHeight":1.2,"bodyWidth":1},
      "garments":["SeedCucumberHoodie"],
      "topPhotoVersion":"F4900000-0000-4000-8000-000000000001","topColor":16711680}}'::jsonb;
  top_name text;
  garment_name text;
  candidate jsonb;
begin
  select * into strict story from public.oi_stories where id='c2400000-0000-4000-8000-000000000011';
  for top_name,garment_name in values
    ('tshirt','SeedCucumberWhiteTshirt'),('hoodie','SeedCucumberHoodie'),
    ('cardigan','SeedCucumberCardigan'),('postech','SeedCucumberPostechJacket') loop
    candidate := jsonb_set(jsonb_set(appearance,'{top}',to_jsonb(top_name)),
      '{seed,garments}',jsonb_build_array(garment_name,'SeedCucumberShorts','SeedCucumberSneakers'));
    perform benchmark_private.oi_check_cucumber_appearance(story,candidate);
    -- The same shirt remains valid without photos or any new optional keys.
    candidate := jsonb_set(candidate,'{topTexture}','false') #- '{seed,topPhotoVersion}' #- '{seed,topColor}';
    perform benchmark_private.oi_check_cucumber_appearance(story,candidate);
  end loop;
  -- Integer color endpoints and UUID case match the app's Codable payload.
  perform benchmark_private.oi_check_cucumber_appearance(story,
    jsonb_set(jsonb_set(appearance,'{topColor}','0'),'{seed,topColor}','0'));
  perform benchmark_private.oi_check_cucumber_appearance(story,
    jsonb_set(jsonb_set(appearance,'{topColor}','16777215'),'{seed,topColor}','16777215'));
  perform pg_temp.reject_seed_photo(story,appearance #- '{seed,topPhotoVersion}','photo without a design version was accepted');
  perform pg_temp.reject_seed_photo(story,appearance #- '{seed,topColor}','photo without its base color was accepted');
  perform pg_temp.reject_seed_photo(story,jsonb_set(appearance,'{seed,topPhotoVersion}','null'),'null design version was accepted');
  perform pg_temp.reject_seed_photo(story,jsonb_set(appearance,'{seed,topPhotoVersion}','"not-a-uuid"'),'invalid design UUID was accepted');
  perform pg_temp.reject_seed_photo(story,jsonb_set(appearance,'{seed,topPhotoVersion}','123'),'numeric design UUID was accepted');
  perform pg_temp.reject_seed_photo(story,jsonb_set(appearance,'{seed,topColor}','16777216'),'out-of-range photo color was accepted');
  perform pg_temp.reject_seed_photo(story,jsonb_set(appearance,'{seed,topColor}','-1'),'negative photo color was accepted');
  perform pg_temp.reject_seed_photo(story,jsonb_set(appearance,'{seed,topColor}','1.5'),'fractional photo color was accepted');
  perform pg_temp.reject_seed_photo(story,jsonb_set(appearance,'{seed,topColor}','"16711680"'),'string photo color was accepted');
  perform pg_temp.reject_seed_photo(story,jsonb_set(appearance,'{seed,topColor}','255'),'mismatched photo color was accepted');
  perform pg_temp.reject_seed_photo(story,jsonb_set(appearance,'{top}','"tshirt"'),'mismatched selected shirt was accepted');
  perform pg_temp.reject_seed_photo(story,jsonb_set(appearance,'{seed,garments}','["seed-costume-cat"]'),'photo on an unsupported costume was accepted');
  perform pg_temp.reject_seed_photo(story,jsonb_set(appearance,'{seed,garments}','["SeedCucumberShorts"]'),'photo without a shirt was accepted');
  perform pg_temp.reject_seed_photo(story,jsonb_set(appearance,'{seed,sources}','{"original":"private-photo"}'),'embedded photo sources were accepted');
  perform pg_temp.reject_seed_photo(story,jsonb_set(appearance,'{topTexture}','false'),'photo metadata without its atlas was accepted');
  perform pg_temp.reject_seed_photo(story,jsonb_set(appearance,'{bottomTexture}','true'),'seed bottom texture was accepted');
  perform pg_temp.reject_seed_photo(story,appearance || '{"costume":"cat"}','photo with legacy costume metadata was accepted');
  delete from storage.objects where name='c2400000-0000-4000-8000-000000000001/c2400000-0000-4000-8000-000000000011/appearance/c2400000-0000-4000-8000-000000000021/top.png';
  perform pg_temp.reject_seed_photo(story,appearance,'photo with a missing atlas file was accepted');
  perform pg_temp.check_result(not has_function_privilege('anon',
    'benchmark_private.oi_check_cucumber_appearance(public.oi_stories,jsonb)','EXECUTE'),'validator was exposed to anon');
  perform pg_temp.check_result(not has_function_privilege('authenticated',
    'benchmark_private.oi_check_cucumber_appearance(public.oi_stories,jsonb)','EXECUTE'),'validator was exposed to authenticated');
end;
$$;
rollback;
