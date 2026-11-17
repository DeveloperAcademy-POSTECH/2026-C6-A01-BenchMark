\set ON_ERROR_STOP on
begin;

create function pg_temp.check_result(value boolean, message text) returns void language plpgsql as $$
begin
  if value is distinct from true then raise exception '%',message; end if;
end;
$$;
create function pg_temp.submission() returns jsonb language sql as $$
  select '{"id":"b3880000-0000-4000-8000-000000000011","revision":1,"ai_review_consent_version":1,
    "card_snapshot_id":"b3880000-0000-4000-8000-000000000031"}'::jsonb;
$$;
create function pg_temp.moderate(snapshot text default null, reason text default null, source text default null) returns jsonb language sql as $$
  select public.oi_moderate_story('b3880000-0000-4000-8000-000000000001',
    'b3880000-0000-4000-8000-000000000021',pg_temp.submission(),snapshot,reason,source);
$$;

insert into auth.users(id) values
 ('b3880000-0000-4000-8000-000000000001'),('b3880000-0000-4000-8000-000000000002');
insert into auth.sessions(id,user_id) values
 ('b3880000-0000-4000-8000-000000000021','b3880000-0000-4000-8000-000000000001'),
 ('b3880000-0000-4000-8000-000000000022','b3880000-0000-4000-8000-000000000002');
insert into benchmark_private.oi_operators values('b3880000-0000-4000-8000-000000000002');

set local role authenticated;
select set_config('request.jwt.claim.sub','b3880000-0000-4000-8000-000000000001',true);
select pg_temp.check_result(public.oi_capabilities()->'auto_story_moderation'='false'::jsonb,'migration preserves current clients until activation');
select public.oi_mutate('save_story',pg_temp.submission()||'{"revision":0,"region_id":"pond","title":"Campus memory",
 "body":"A walk by the pond","theme":"감사","emotion":"기쁨","cucumber_name":"테스트오이",
 "cucumber_asset":"OiCats","card_asset":"MYBasicCard","latitude":36.01261057,"longitude":129.31972687}');
reset role;
insert into storage.objects(bucket_id,name,metadata) values
 ('oi-story-media','b3880000-0000-4000-8000-000000000001/b3880000-0000-4000-8000-000000000011/photo.jpg',
  '{"mimetype":"image/jpeg","size":100}'),
 ('oi-story-media','b3880000-0000-4000-8000-000000000001/b3880000-0000-4000-8000-000000000011/card/b3880000-0000-4000-8000-000000000031.png',
  '{"mimetype":"image/png","size":100}');
insert into public.oi_story_media(story_id,object_path,position)
select 'b3880000-0000-4000-8000-000000000011',name,0 from storage.objects where name like 'b388%/photo.jpg';
set local role authenticated;
select pg_temp.check_result(public.oi_mutate('submit_story',pg_temp.submission()) @> '{"status":"pending","revision":2}', 'legacy pending fixture');
reset role;
update benchmark_private.oi_story_creation_settings set auto_moderation_enabled=true where singleton;
-- Stage an AI review as a concurrent caller before manual approval.
set local role service_role;
select public.oi_moderate_story('b3880000-0000-4000-8000-000000000001',
 'b3880000-0000-4000-8000-000000000021',pg_temp.submission()||'{"revision":2}') as prepared \gset
set local role authenticated;
select set_config('request.jwt.claim.sub','b3880000-0000-4000-8000-000000000001',true);
do $$ begin
  begin
    perform public.oi_mutate('review_story',pg_temp.submission()||'{"revision":2,"status":"published"}');
    raise exception 'nonoperator approved';
  exception when insufficient_privilege then null; end;
end; $$;
select set_config('request.jwt.claim.sub','b3880000-0000-4000-8000-000000000002',true);
select pg_temp.check_result(public.oi_capabilities() @> '{"operator":true,"auto_story_moderation":true,"operator_manual_story_review":true}', 'AI and operator manual capabilities coexist');
do $$ begin
  begin
    perform public.oi_mutate('review_story',pg_temp.submission()||'{"status":"published"}');
    raise exception 'stale operator revision approved';
  exception when serialization_failure then null; end;
end; $$;
select pg_temp.check_result(public.oi_mutate('review_story',pg_temp.submission()||'{"revision":2,"status":"published"}')
 @> '{"status":"published","revision":3}', 'operator approves pending while AI remains enabled');
set local role service_role;
select set_config('test.manual_snapshot', :'prepared'::jsonb->>'snapshot',true);
do $$ begin
  begin
    perform public.oi_moderate_story('b3880000-0000-4000-8000-000000000001',
      'b3880000-0000-4000-8000-000000000021',pg_temp.submission()||'{"revision":2}',current_setting('test.manual_snapshot'));
    raise exception 'late AI overwrote operator decision';
  exception when sqlstate 'PT409' then null; end;
end; $$;
reset role;
select pg_temp.check_result(exists(select 1 from benchmark_private.oi_audit
 where actor_id='b3880000-0000-4000-8000-000000000002' and action='review_story'
 and target_id='b3880000-0000-4000-8000-000000000011'), 'manual decision records operator audit');
select pg_temp.check_result(benchmark_private.oi_auto_moderation_enabled(), 'manual approval never disables AI');
set local role authenticated;
select pg_temp.check_result(public.oi_mutate('review_story',pg_temp.submission()||'{"revision":3,"status":"hidden"}') @> '{"status":"hidden","revision":4}', 'operator can hide');
select pg_temp.check_result(public.oi_mutate('review_story',pg_temp.submission()||'{"revision":4,"status":"published"}') @> '{"status":"published","revision":5}', 'operator can restore hidden');
reset role;
delete from benchmark_private.oi_operators where user_id='b3880000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ begin
  begin
    perform public.oi_mutate('review_story',pg_temp.submission()||'{"revision":5,"status":"hidden"}');
    raise exception 'revoked operator changed publication';
  exception when insufficient_privilege then null; end;
end; $$;
rollback;
