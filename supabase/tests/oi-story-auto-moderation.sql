\set ON_ERROR_STOP on
begin;

create function pg_temp.check_result(value boolean, message text) returns void language plpgsql as $$
begin
  if value is distinct from true then raise exception '%',message; end if;
end;
$$;
create function pg_temp.submission() returns jsonb language sql as $$
  select '{"id":"a3880000-0000-4000-8000-000000000011","revision":1,"ai_review_consent_version":1,
    "card_snapshot_id":"a3880000-0000-4000-8000-000000000031"}'::jsonb;
$$;
create function pg_temp.moderate(snapshot text default null, reason text default null, source text default null) returns jsonb language sql as $$
  select public.oi_moderate_story('a3880000-0000-4000-8000-000000000001',
    'a3880000-0000-4000-8000-000000000021',pg_temp.submission(),snapshot,reason,source);
$$;

insert into auth.users(id) values
 ('a3880000-0000-4000-8000-000000000001'),('a3880000-0000-4000-8000-000000000002');
insert into auth.sessions(id,user_id) values
 ('a3880000-0000-4000-8000-000000000021','a3880000-0000-4000-8000-000000000001'),
 ('a3880000-0000-4000-8000-000000000022','a3880000-0000-4000-8000-000000000002');
insert into benchmark_private.oi_operators values('a3880000-0000-4000-8000-000000000002');

set local role authenticated;
select set_config('request.jwt.claim.sub','a3880000-0000-4000-8000-000000000001',true);
select pg_temp.check_result(public.oi_capabilities()->'auto_story_moderation'='false'::jsonb,'migration preserves current clients until activation');
select public.oi_mutate('save_story',pg_temp.submission()||'{"revision":0,"region_id":"pond","title":"Campus memory",
 "body":"A walk by the pond","theme":"감사","emotion":"기쁨","cucumber_name":"테스트오이",
 "cucumber_asset":"OiCats","card_asset":"MYBasicCard","latitude":36.01261057,"longitude":129.31972687}');
reset role;
insert into storage.objects(bucket_id,name,metadata) values
 ('oi-story-media','a3880000-0000-4000-8000-000000000001/a3880000-0000-4000-8000-000000000011/photo.jpg',
  '{"mimetype":"image/jpeg","size":100}'),
 ('oi-story-media','a3880000-0000-4000-8000-000000000001/a3880000-0000-4000-8000-000000000011/card/a3880000-0000-4000-8000-000000000031.png',
  '{"mimetype":"image/png","size":100}');
insert into public.oi_story_media(story_id,object_path,position)
select 'a3880000-0000-4000-8000-000000000011',name,0 from storage.objects where name like 'a388%/photo.jpg';
update benchmark_private.oi_story_creation_settings set auto_moderation_enabled=true where singleton;

set local role authenticated;
select pg_temp.check_result(public.oi_capabilities()->'auto_story_moderation'='true'::jsonb,'active client capability');
do $$
begin
  perform set_config('benchmark.story_moderation_step','publish',true);
  begin
    perform public.oi_mutate('submit_story',pg_temp.submission());
    raise exception 'direct submission bypass';
  exception when sqlstate 'PT426' then null; end;
  begin
    perform pg_temp.moderate();
    raise exception 'user can call service RPC';
  exception when insufficient_privilege then null; end;
end;
$$;
select set_config('request.jwt.claim.sub','a3880000-0000-4000-8000-000000000002',true);
do $$
begin
  perform public.oi_mutate('review_story',pg_temp.submission()||'{"status":"published"}');
  raise exception 'operator can publish an unplanted draft';
exception when invalid_parameter_value then null;
end;
$$;

set local role service_role;
do $$
begin
  begin
    perform public.oi_moderate_story('a3880000-0000-4000-8000-000000000002',
      'a3880000-0000-4000-8000-000000000022',pg_temp.submission());
    raise exception 'other author could review draft';
  exception when insufficient_privilege then null; end;
  begin
    perform public.oi_moderate_story('a3880000-0000-4000-8000-000000000001',
      'a3880000-0000-4000-8000-000000000022',pg_temp.submission());
    raise exception 'mismatched session was accepted';
  exception when sqlstate 'PT401' then null; end;
end;
$$;
select pg_temp.moderate() as prepared \gset
select pg_temp.check_result((:'prepared'::jsonb->>'title')='Campus memory'
  and jsonb_array_length(:'prepared'::jsonb->'photos')=1
  and jsonb_array_length(:'prepared'::jsonb->'cards')=1,'snapshot contains only the intended story and rendered files');

reset role;
select pg_temp.check_result((select status='draft' and revision=1 and card_snapshot_id is null
  from public.oi_stories where id=(pg_temp.submission()->>'id')::uuid),'prepare or rejection keeps the original draft');
update storage.objects set metadata=metadata||'{"size":101}' where name like 'a388%/photo.jpg';
set local role service_role;
select set_config('test.first_snapshot', :'prepared'::jsonb->>'snapshot', true);
do $$
begin
  perform pg_temp.moderate(current_setting('test.first_snapshot'));
  raise exception 'changed image was published';
exception when sqlstate 'PT409' then null;
end;
$$;
select pg_temp.moderate() as prepared \gset
select pg_temp.check_result(pg_temp.moderate(:'prepared'::jsonb->>'snapshot','profanity','story')
  @> '{"status":"rejected","revision":1,"reason":"profanity"}','rejection persists without publishing');

set local role authenticated;
select pg_temp.check_result(public.oi_my_story_reviews()
  @> '[{"revision":1,"status":"rejected","reason":"profanity"}]','owner sees the rejected review');
do $$
begin
  perform public.oi_plant_story((pg_temp.submission()->>'id')::uuid,1);
  raise exception 'rejected story was published';
exception when sqlstate 'PT409' then null;
end;
$$;
set local role service_role;
select pg_temp.moderate() as prepared \gset
select pg_temp.check_result(pg_temp.moderate(:'prepared'::jsonb->>'snapshot')
  @> '{"status":"approved","revision":2,"story":{"status":"draft","card_snapshot_id":"a3880000-0000-4000-8000-000000000031"}}',
  'approval saves the reviewed assets while the story remains private');

set local role anon;
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claims','{}',true);
select pg_temp.check_result(not exists(select 1 from public.oi_stories
  where id=(pg_temp.submission()->>'id')::uuid),'approved draft is still private');
reset role;
update storage.objects set metadata=metadata||'{"size":102}' where name like 'a388%/photo.jpg';
set local role authenticated;
select set_config('request.jwt.claim.sub','a3880000-0000-4000-8000-000000000001',true);
do $$
begin
  perform public.oi_plant_story((pg_temp.submission()->>'id')::uuid,2);
  raise exception 'changed asset was planted';
exception when sqlstate 'PT409' then null;
end;
$$;
reset role;
update storage.objects set metadata=metadata||'{"size":101}' where name like 'a388%/photo.jpg';
set local role authenticated;
select pg_temp.check_result(public.oi_plant_story((pg_temp.submission()->>'id')::uuid,2)
  @> '{"status":"published","revision":3}','owner explicitly plants the reviewed story');

set local role anon;
select pg_temp.check_result((select status='published' from public.oi_stories
  where id=(pg_temp.submission()->>'id')::uuid),'published story is visible on the normal read path');
set local role authenticated;
select set_config('request.jwt.claim.sub','a3880000-0000-4000-8000-000000000002',true);
select pg_temp.check_result(public.oi_mutate('review_story',pg_temp.submission()||'{"revision":3,"status":"hidden"}')
  @> '{"status":"hidden"}','operators can still remove a published story');
-- A prepared but abandoned legacy review must leave the original submission in the queue.
reset role;
update public.oi_stories set status='pending', revision=5 where id=(pg_temp.submission()->>'id')::uuid;
delete from benchmark_private.oi_story_moderation_quota;
create function pg_temp.moderate_pending(revision integer, snapshot text default null, reason text default null, source text default null)
returns jsonb language sql as $$
  select public.oi_moderate_story('a3880000-0000-4000-8000-000000000001',
    'a3880000-0000-4000-8000-000000000021',pg_temp.submission()||jsonb_build_object('revision',revision),
    snapshot,reason,source);
$$;
set local role service_role;
select pg_temp.moderate_pending(5) as legacy_prepared \gset
reset role;
select pg_temp.check_result((select status='pending' and revision=5 from public.oi_stories
  where id=(pg_temp.submission()->>'id')::uuid),'abandoned AI request preserves original pending submission');
set local role service_role;
select pg_temp.check_result(pg_temp.moderate_pending(5,:'legacy_prepared'::jsonb->>'snapshot','profanity','story')
  @> '{"status":"rejected","revision":6,"story":{"status":"draft","revision":6}}',
  'legacy rejection atomically moves the story to an editable draft');
reset role;
update public.oi_stories set status='pending', revision=7 where id=(pg_temp.submission()->>'id')::uuid;
set local role service_role;
select pg_temp.moderate_pending(7) as legacy_prepared \gset
select pg_temp.check_result(pg_temp.moderate_pending(7,:'legacy_prepared'::jsonb->>'snapshot')
  @> '{"status":"approved","revision":8,"story":{"status":"draft","revision":8}}',
  'legacy approval commits an approved draft without publishing');
set local role authenticated;
select set_config('request.jwt.claim.sub','a3880000-0000-4000-8000-000000000001',true);
select pg_temp.check_result(public.oi_my_story_reviews()
  @> '[{"revision":8,"status":"approved"}]','a fresh client can recover the completed legacy verdict');
rollback;
