\set ON_ERROR_STOP on
begin;
create function pg_temp.check_result(value boolean,message text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.payload(p_id uuid,p_revision integer) returns jsonb language sql as $$
  select jsonb_build_object('id',p_id,'revision',p_revision,'region_id','pond','title','Synthetic continuation',
    'body','Synthetic story','theme','감사','emotion','기쁨','cucumber_name','테스트오이',
    'cucumber_asset','OiCats','card_asset','MYBasicCard','latitude',36.01261057,'longitude',129.31972687);
$$;
insert into auth.users(id) values
 ('c4180000-0000-4000-8000-000000000001'),('c4180000-0000-4000-8000-000000000002'),
 ('c4180000-0000-4000-8000-000000000003');
insert into auth.sessions(id,user_id) values
 ('c4180000-0000-4000-8000-000000000021','c4180000-0000-4000-8000-000000000002'),
 ('c4180000-0000-4000-8000-000000000022','c4180000-0000-4000-8000-000000000001'),
 ('c4180000-0000-4000-8000-000000000023','c4180000-0000-4000-8000-000000000003');
insert into public.oi_stories(id,user_id,storage_owner_id,region_id,title,body,theme,emotion,cucumber_name,cucumber_asset,card_asset,latitude,longitude,status)
select ('c4180000-0000-4000-8000-00000000000'||i)::uuid,
  ('c4180000-0000-4000-8000-00000000000'||(case when i=5 then 2 else 1 end))::uuid,
  ('c4180000-0000-4000-8000-00000000000'||(case when i=5 then 2 else 1 end))::uuid,
  'pond','Synthetic parent','Synthetic parent body','감사','기쁨','테스트오이','OiCats','MYBasicCard',36.01261057,129.31972687,
  case when i=6 then 'hidden' else 'published' end from generate_series(4,7) i;

set local role authenticated;
select set_config('request.jwt.claim.sub','c4180000-0000-4000-8000-000000000002',true);
select pg_temp.check_result(public.oi_capabilities()->'story_continuations'='true'::jsonb,'capability missing');
select public.oi_mutate('save_story',pg_temp.payload('c4180000-0000-4000-8000-000000000011',0)||
  '{"continued_from_story_id":"c4180000-0000-4000-8000-000000000004"}') as saved \gset
select pg_temp.check_result(:'saved'::jsonb->>'continued_from_story_id'='c4180000-0000-4000-8000-000000000004','target receipt missing');
select public.oi_mutate('save_story',pg_temp.payload('c4180000-0000-4000-8000-000000000011',1)) as saved \gset
select pg_temp.check_result(:'saved'::jsonb->>'continued_from_story_id'='c4180000-0000-4000-8000-000000000004','old payload lost relation');
do $$
declare target uuid;
begin
  foreach target in array array['c4180000-0000-4000-8000-000000000005'::uuid,
    'c4180000-0000-4000-8000-000000000006'::uuid,'c4180000-0000-4000-8000-000000000099'::uuid,
    'c4180000-0000-4000-8000-000000000011'::uuid] loop
    begin
      perform public.oi_mutate('save_story',pg_temp.payload('c4180000-0000-4000-8000-000000000011',2)||
        jsonb_build_object('continued_from_story_id',target));
      raise exception 'Invalid/own/hidden target accepted';
    exception when invalid_parameter_value then null; end;
  end loop;
end; $$;
select public.oi_mutate('save_story',pg_temp.payload('c4180000-0000-4000-8000-000000000011',2)||
  '{"continued_from_story_id":null}') as saved \gset
select pg_temp.check_result(:'saved'::jsonb->'continued_from_story_id'='null'::jsonb,'explicit null did not clear');
select public.oi_mutate('save_story',pg_temp.payload('c4180000-0000-4000-8000-000000000011',3)||
  '{"continued_from_story_id":"c4180000-0000-4000-8000-000000000004"}') as saved \gset
set local role anon;
select pg_temp.check_result(public.oi_story_continuations('c4180000-0000-4000-8000-000000000004')->>'total'='0','draft relation leaked');
do $$ begin
  begin perform 1 from benchmark_private.oi_story_continuations; raise exception 'Private relation table readable';
  exception when insufficient_privilege then null; end;
  begin perform public.oi_story_continuations(p_mine=>true); raise exception 'Anonymous private inbox readable';
  exception when insufficient_privilege then null; end;
end; $$;
reset role;
select pg_temp.check_result(not exists(select 1 from information_schema.columns
  where table_schema='public' and table_name='oi_stories' and column_name='continued_from_story_id'),'raw public row leaks hidden parent UUID');

-- Use the actual service-only AI approval and author planting path, not an operator bypass.
insert into storage.objects(bucket_id,name,metadata) values
 ('oi-story-media','c4180000-0000-4000-8000-000000000002/c4180000-0000-4000-8000-000000000011/photo.jpg','{"mimetype":"image/jpeg","size":100}'),
 ('oi-story-media','c4180000-0000-4000-8000-000000000002/c4180000-0000-4000-8000-000000000011/card/c4180000-0000-4000-8000-000000000031.png','{"mimetype":"image/png","size":100}');
insert into public.oi_story_media(story_id,object_path,position) values
 ('c4180000-0000-4000-8000-000000000011','c4180000-0000-4000-8000-000000000002/c4180000-0000-4000-8000-000000000011/photo.jpg',0);
update benchmark_private.oi_story_creation_settings set auto_moderation_enabled=true;
select set_config('request.jwt.claim.sub','c4180000-0000-4000-8000-000000000002',true);
-- A relation-free story must retain exactly the existing approved snapshot contract.
update benchmark_private.oi_story_continuations set parent_story_id=null
 where child_story_id='c4180000-0000-4000-8000-000000000011';
select pg_temp.check_result(
 benchmark_private.oi_story_review_snapshot('{"id":"c4180000-0000-4000-8000-000000000011","revision":4,"card_snapshot_id":"c4180000-0000-4000-8000-000000000031"}')->>'snapshot'
 = benchmark_private.oi_story_review_snapshot_continuation_base('{"id":"c4180000-0000-4000-8000-000000000011","revision":4,"card_snapshot_id":"c4180000-0000-4000-8000-000000000031"}')->>'snapshot',
 'relation-free snapshot changed');
update benchmark_private.oi_story_continuations set parent_story_id='c4180000-0000-4000-8000-000000000004'
 where child_story_id='c4180000-0000-4000-8000-000000000011';
set local role service_role;
select public.oi_moderate_story('c4180000-0000-4000-8000-000000000002','c4180000-0000-4000-8000-000000000021',
  '{"id":"c4180000-0000-4000-8000-000000000011","revision":4,"ai_review_consent_version":1,"card_snapshot_id":"c4180000-0000-4000-8000-000000000031"}') as prepared \gset
select public.oi_moderate_story('c4180000-0000-4000-8000-000000000002','c4180000-0000-4000-8000-000000000021',
  '{"id":"c4180000-0000-4000-8000-000000000011","revision":4,"ai_review_consent_version":1,"card_snapshot_id":"c4180000-0000-4000-8000-000000000031"}',
  :'prepared'::jsonb->>'snapshot') as reviewed \gset
reset role;
update benchmark_private.oi_story_continuations set parent_story_id='c4180000-0000-4000-8000-000000000007'
  where child_story_id='c4180000-0000-4000-8000-000000000011';
set local role authenticated;
select set_config('request.jwt.claim.sub','c4180000-0000-4000-8000-000000000002',true);
do $$ begin
  perform public.oi_plant_story('c4180000-0000-4000-8000-000000000011',5);
  raise exception 'Changed relationship bypassed approved snapshot';
exception when sqlstate 'PT409' then null; end; $$;
reset role;
update benchmark_private.oi_story_continuations set parent_story_id='c4180000-0000-4000-8000-000000000004'
  where child_story_id='c4180000-0000-4000-8000-000000000011';
set local role authenticated;
select set_config('request.jwt.claim.sub','c4180000-0000-4000-8000-000000000001',true);
select pg_temp.check_result(public.oi_story_continuations(p_mine=>true)->>'total'='0','AI-approved private child leaked');
select set_config('request.jwt.claim.sub','c4180000-0000-4000-8000-000000000002',true);
select public.oi_plant_story('c4180000-0000-4000-8000-000000000011',5);
select set_config('request.jwt.claim.sub','c4180000-0000-4000-8000-000000000001',true);
select pg_temp.check_result(public.oi_story_continuations(p_mine=>true)->>'total'='1','parent cannot see planted child');
do $$ begin
  begin
    perform public.oi_read_story_continuation('c4180000-0000-4000-8000-000000000011',array['c4180000-0000-4000-8000-000000000002'::uuid]);
    raise exception 'Blocked child notification opened';
  exception when invalid_parameter_value then null; end;
end; $$;
select set_config('request.jwt.claim.sub','c4180000-0000-4000-8000-000000000003',true);
do $$ begin
  perform public.oi_read_story_continuation('c4180000-0000-4000-8000-000000000011');
  raise exception 'Stranger marked parent notification read';
exception when invalid_parameter_value then null; end; $$;
select set_config('request.jwt.claim.sub','c4180000-0000-4000-8000-000000000001',true);
select public.oi_read_story_continuation('c4180000-0000-4000-8000-000000000011') as read_receipt \gset
select pg_temp.check_result(:'read_receipt'::jsonb->'story'->>'status'='published','read receipt lacks current public story');
select pg_temp.check_result(public.oi_story_continuations(p_mine=>true)->'items'->0->>'read_at' is not null,'read status missing');
set local role anon;
select pg_temp.check_result(public.oi_story_continuation_counts(array['c4180000-0000-4000-8000-000000000004'::uuid])->0->>'count'='1','public count mismatch');
select pg_temp.check_result(public.oi_story_continuations('c4180000-0000-4000-8000-000000000004')->'items'->0->'read_at'='null'::jsonb,'private read status leaked');
select pg_temp.check_result(public.oi_story_continuations('c4180000-0000-4000-8000-000000000004',p_blocked=>array['c4180000-0000-4000-8000-000000000002'::uuid])->>'total'='0','blocked author relation leaked');
reset role;
do $$ begin
  perform benchmark_private.oi_check_continuation('c4180000-0000-4000-8000-000000000004',
    'c4180000-0000-4000-8000-000000000011','c4180000-0000-4000-8000-000000000001');
  raise exception 'Indirect cycle accepted';
exception when invalid_parameter_value then null; end; $$;
-- Pending account deletion must match the existing public-story RLS boundary.
insert into benchmark_private.oi_account_deletions(account_id) values('c4180000-0000-4000-8000-000000000001');
set local role anon;
select pg_temp.check_result(not exists(select 1 from public.oi_stories where id='c4180000-0000-4000-8000-000000000004'),'existing story RLS did not hide deleting parent');
select pg_temp.check_result(public.oi_story_continuations('c4180000-0000-4000-8000-000000000004')->>'total'='0','deleting parent relation leaked');
select pg_temp.check_result(public.oi_story_continuation_counts(array['c4180000-0000-4000-8000-000000000004'::uuid])='[]'::jsonb,'deleting parent counted');
set local role authenticated;
select set_config('request.jwt.claim.sub','c4180000-0000-4000-8000-000000000002',true);
select pg_temp.check_result(public.oi_my_story_continuation_targets()->0->'continued_from_story_id'='null'::jsonb,'deleting parent UUID leaked in draft metadata');
do $$ begin
 perform public.oi_mutate('save_story',pg_temp.payload('c4180000-0000-4000-8000-000000000019',0)||
   '{"continued_from_story_id":"c4180000-0000-4000-8000-000000000004"}');
 raise exception 'Deleting parent accepted as new target';
exception when invalid_parameter_value then null; end; $$;
reset role;
delete from benchmark_private.oi_account_deletions where account_id='c4180000-0000-4000-8000-000000000001';
insert into benchmark_private.oi_account_deletions(account_id) values('c4180000-0000-4000-8000-000000000002');
set local role anon;
select pg_temp.check_result(not exists(select 1 from public.oi_stories where id='c4180000-0000-4000-8000-000000000011'),'existing story RLS did not hide deleting child');
select pg_temp.check_result(public.oi_story_continuations('c4180000-0000-4000-8000-000000000004')->>'total'='0','deleting child relation leaked');
select pg_temp.check_result(public.oi_story_continuation_counts(array['c4180000-0000-4000-8000-000000000004'::uuid])->0->>'count'='0','deleting child counted');
set local role authenticated;
select set_config('request.jwt.claim.sub','c4180000-0000-4000-8000-000000000001',true);
select pg_temp.check_result(public.oi_story_continuations(p_mine=>true)->>'total'='0','deleting child remained in notifications');
do $$ begin
 perform public.oi_read_story_continuation('c4180000-0000-4000-8000-000000000011');
 raise exception 'Deleting child opened from notification';
exception when invalid_parameter_value then null; end; $$;
reset role;
delete from benchmark_private.oi_account_deletions where account_id='c4180000-0000-4000-8000-000000000002';
insert into benchmark_private.oi_content_restrictions(member_id,note)
  values('c4180000-0000-4000-8000-000000000001','Synthetic parent restriction');
set local role anon;
select pg_temp.check_result(public.oi_story_continuations('c4180000-0000-4000-8000-000000000004')->>'total'='0','restricted parent leaked');
select pg_temp.check_result(public.oi_story_continuation_counts(array['c4180000-0000-4000-8000-000000000004'::uuid])='[]'::jsonb,'restricted parent counted');
reset role;
delete from benchmark_private.oi_content_restrictions where member_id='c4180000-0000-4000-8000-000000000001';
insert into benchmark_private.oi_content_restrictions(member_id,note)
  values('c4180000-0000-4000-8000-000000000002','Synthetic restriction');
set local role anon;
select pg_temp.check_result(public.oi_story_continuations('c4180000-0000-4000-8000-000000000004')->>'total'='0','restricted child counted');
reset role;
delete from benchmark_private.oi_content_restrictions where member_id='c4180000-0000-4000-8000-000000000002';
update public.oi_stories set status='hidden' where id='c4180000-0000-4000-8000-000000000004';
set local role anon;
select pg_temp.check_result(public.oi_story_continuations('c4180000-0000-4000-8000-000000000004')->>'total'='0','hidden parent leaked');
select pg_temp.check_result(public.oi_story_continuation_counts(array['c4180000-0000-4000-8000-000000000004'::uuid])='[]'::jsonb,'hidden parent counted');
reset role;
update public.oi_stories set status='published' where id='c4180000-0000-4000-8000-000000000004';
update public.oi_stories set status='hidden' where id='c4180000-0000-4000-8000-000000000011';
set local role anon;
select pg_temp.check_result(public.oi_story_continuations('c4180000-0000-4000-8000-000000000004')->>'total'='0','hidden child leaked');
reset role;
update public.oi_stories set status='published' where id='c4180000-0000-4000-8000-000000000011';
select pg_temp.check_result((select count(*)=1 and read_at is not null from benchmark_private.oi_story_continuations
  where child_story_id='c4180000-0000-4000-8000-000000000011' group by read_at),'republication duplicated/reset notification');
update public.oi_stories set status='deleted' where id='c4180000-0000-4000-8000-000000000004';
select pg_temp.check_result((select parent_story_id is null from benchmark_private.oi_story_continuations
  where child_story_id='c4180000-0000-4000-8000-000000000011'),'logical parent deletion did not unlink');
select pg_temp.check_result((select status='published' from public.oi_stories where id='c4180000-0000-4000-8000-000000000011'),'parent deletion deleted child');

-- Multiple children and stable keyset pagination; draft creation time is not the order.
insert into public.oi_stories(id,user_id,storage_owner_id,region_id,title,body,theme,emotion,cucumber_name,cucumber_asset,card_asset,latitude,longitude,status)
select ('c4180000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
  'c4180000-0000-4000-8000-000000000002','c4180000-0000-4000-8000-000000000002',
  'pond','Synthetic child','Synthetic body','감사','기쁨','테스트오이','OiCats','MYBasicCard',36.01261057,129.31972687,'draft'
  from generate_series(1,25) i;
insert into benchmark_private.oi_story_continuations(child_story_id,parent_story_id)
  select id,'c4180000-0000-4000-8000-000000000007' from public.oi_stories
  where id::text like 'c4180000-0000-4000-8000-0000000001%';
update public.oi_stories set status='published' where id::text like 'c4180000-0000-4000-8000-0000000001%';
set local role anon;
select public.oi_story_continuations('c4180000-0000-4000-8000-000000000007') as page \gset
select pg_temp.check_result(:'page'::jsonb->>'total'='25' and jsonb_array_length(:'page'::jsonb->'items')=20,'page/total mismatch');
select public.oi_story_continuations('c4180000-0000-4000-8000-000000000007',
  p_before=>(:'page'::jsonb->'next_cursor'->>'published_at')::timestamptz,
  p_before_id=>(:'page'::jsonb->'next_cursor'->>'child_story_id')::uuid) as next_page \gset
select pg_temp.check_result(jsonb_array_length(:'next_page'::jsonb->'items')=5 and
  :'next_page'::jsonb->'next_cursor'='null'::jsonb,'keyset pagination repeated/skipped children');
select pg_temp.check_result((:'page'::jsonb->'items'->0->'story'->>'status')='published','page lacks atomic approved story projection');
reset role;
-- Actual canonical merge preserves child references and moves the private owner target view.
set local role service_role;
select public.oi_merge_accounts('preview','c4180000-0000-4000-8000-000000000041',
 'c4180000-0000-4000-8000-000000000003','c4180000-0000-4000-8000-000000000002',
 'c4180000-0000-4000-8000-000000000023','c4180000-0000-4000-8000-000000000021')->>'challenge_id' as challenge \gset
select public.oi_merge_accounts('confirm','c4180000-0000-4000-8000-000000000041',
 'c4180000-0000-4000-8000-000000000003','c4180000-0000-4000-8000-000000000002',
 'c4180000-0000-4000-8000-000000000023','c4180000-0000-4000-8000-000000000021',:'challenge',true);
set local role authenticated;
select set_config('request.jwt.claim.sub','c4180000-0000-4000-8000-000000000002',true);
select pg_temp.check_result(jsonb_array_length(public.oi_my_story_continuation_targets())=26,'merged member lost own relation metadata');
set local role anon;
select pg_temp.check_result(public.oi_story_continuations('c4180000-0000-4000-8000-000000000007')->>'total'='25','merge lost public links');
reset role;
-- Account deletion removes the parent and unlinks relations without deleting other owners' children.
set local role service_role;
select public.oi_delete_account('prepare','c4180000-0000-4000-8000-000000000001','c4180000-0000-4000-8000-000000000022',
 'c4180000-0000-4000-8000-000000000001','c4180000-0000-4000-8000-000000000022','c4180000-0000-4000-8000-000000000001');
select public.oi_delete_account('finish','c4180000-0000-4000-8000-000000000001','c4180000-0000-4000-8000-000000000022',
 'c4180000-0000-4000-8000-000000000001','c4180000-0000-4000-8000-000000000022','c4180000-0000-4000-8000-000000000001');
reset role;
select pg_temp.check_result(not exists(select 1 from public.oi_stories where id='c4180000-0000-4000-8000-000000000007'),'account deletion retained parent');
select pg_temp.check_result(not exists(select 1 from benchmark_private.oi_story_continuations where parent_story_id is not null),
  'physical parent deletion did not null references');
select pg_temp.check_result((select count(*) from public.oi_stories where id::text like 'c4180000-0000-4000-8000-0000000001%')=25,'physical parent deletion cascaded to children');
rollback;
