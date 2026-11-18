\set ON_ERROR_STOP on
begin;
create function pg_temp.check_result(value boolean, message text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.submission() returns jsonb language sql as $$
select '{"id":"a5080000-0000-4000-8000-000000000011","revision":1,
 "card_snapshot_id":"a5080000-0000-4000-8000-000000000031"}'::jsonb; $$;
create function pg_temp.publish() returns jsonb language sql as $$
select public.oi_publish_showcase_story('a5080000-0000-4000-8000-000000000001',
 'a5080000-0000-4000-8000-000000000021',pg_temp.submission()); $$;
insert into auth.users(id) values
 ('a5080000-0000-4000-8000-000000000001'),('a5080000-0000-4000-8000-000000000002');
insert into auth.sessions(id,user_id) values
 ('a5080000-0000-4000-8000-000000000021','a5080000-0000-4000-8000-000000000001'),
 ('a5080000-0000-4000-8000-000000000022','a5080000-0000-4000-8000-000000000002');
insert into benchmark_private.oi_operators values('a5080000-0000-4000-8000-000000000002');

set local role authenticated;
select set_config('request.jwt.claim.sub','a5080000-0000-4000-8000-000000000001',true);

select public.oi_mutate('save_story',pg_temp.submission()||'{"revision":0,"region_id":"pond","title":"Campus memory",
 "body":"A walk by the pond","theme":"감사","emotion":"기쁨","cucumber_name":"테스트오이",
 "cucumber_asset":"OiCats","card_asset":"MYBasicCard","latitude":36.01261057,"longitude":129.31972687}');
reset role;
insert into storage.objects(bucket_id,name,metadata) values
 ('oi-story-media','a5080000-0000-4000-8000-000000000001/a5080000-0000-4000-8000-000000000011/photo.jpg',
  '{"mimetype":"image/jpeg","size":100}'),
 ('oi-story-media','a5080000-0000-4000-8000-000000000001/a5080000-0000-4000-8000-000000000011/card/a5080000-0000-4000-8000-000000000031.png',
  '{"mimetype":"image/png","size":100}');
insert into public.oi_story_media(story_id,object_path,position)
select 'a5080000-0000-4000-8000-000000000011',name,0 from storage.objects where name like 'a508%/photo.jpg';
update benchmark_private.oi_story_creation_settings set auto_moderation_enabled=true where singleton;


set local role authenticated;
do $$ begin
 begin perform pg_temp.publish(); raise exception 'authenticated user called service RPC';
 exception when insufficient_privilege then null; end;
 begin perform public.oi_plant_story((pg_temp.submission()->>'id')::uuid,1); raise exception 'regular planting bypassed AI';
 exception when sqlstate 'PT409' then null; end;
end; $$;
set local role service_role;
do $$ begin
 begin perform pg_temp.publish(); raise exception 'disabled showcase was accepted';
 exception when sqlstate 'PT503' then null; end;
end; $$;
reset role;
update benchmark_private.oi_story_creation_settings set testflight_showcase_enabled=true;
set local role service_role;
do $$ begin
 begin perform public.oi_publish_showcase_story('a5080000-0000-4000-8000-000000000002',
  'a5080000-0000-4000-8000-000000000022',pg_temp.submission()); raise exception 'other author published';
 exception when insufficient_privilege then null; end;
 begin perform public.oi_publish_showcase_story('a5080000-0000-4000-8000-000000000001',
  'a5080000-0000-4000-8000-000000000022',pg_temp.submission()); raise exception 'mismatched session accepted';
 exception when sqlstate 'PT401' then null; end;
 begin perform public.oi_publish_showcase_story('a5080000-0000-4000-8000-000000000001',
  'a5080000-0000-4000-8000-000000000021',pg_temp.submission()||'{"revision":999}'); raise exception 'stale revision accepted';
 exception when sqlstate 'PT409' then null; end;
end; $$;
reset role;
savepoint before_checks;
set local role service_role;
select pg_temp.check_result(pg_temp.publish()->>'status'='published','unreviewed TF draft was not published');
rollback to before_checks;
update benchmark_private.oi_story_creation_settings set unapproved_drafts_enabled=false;
set local role service_role;
do $$ begin
 begin perform pg_temp.publish(); raise exception 'publication bypassed writing pause';
 exception when insufficient_privilege then null; end;
end; $$;
rollback to before_checks;
insert into benchmark_private.oi_content_restrictions(member_id,note)
values ('a5080000-0000-4000-8000-000000000001','Showcase restriction fixture');
set local role service_role;
do $$ begin
 begin perform pg_temp.publish(); raise exception 'restricted author published';
 exception when insufficient_privilege then null; end;
end; $$;
rollback to before_checks;
-- A rejection does not block the explicit TF exception and must not turn into a fake approval.
insert into benchmark_private.oi_story_moderation_results(story_id,revision,snapshot,reason,source)
values ((pg_temp.submission()->>'id')::uuid,1,'rejected-fixture','profanity','story');
savepoint before_publication;
set local role service_role;
select pg_temp.check_result(pg_temp.publish()->>'status'='published','TF rejected draft was not published');
reset role;
select pg_temp.check_result(not exists(select 1 from benchmark_private.oi_story_moderation_results
 where story_id=(pg_temp.submission()->>'id')::uuid and reason is null),'fake AI approval was recorded');
rollback to before_publication;
update public.oi_stories set status='pending' where id=(pg_temp.submission()->>'id')::uuid;
set local role service_role;
select pg_temp.check_result(pg_temp.publish()->>'status'='published','legacy pending draft was not published');
rollback to before_publication;
delete from public.oi_story_media where story_id=(pg_temp.submission()->>'id')::uuid;
set local role service_role;
do $$ begin
 begin perform pg_temp.publish(); raise exception 'missing photo published';
 exception when invalid_parameter_value then null; end;
end; $$;
rollback;
