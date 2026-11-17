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
rollback;
