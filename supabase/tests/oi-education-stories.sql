begin;
create function pg_temp.assert_true(value boolean,description text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception 'FAIL: %',description;end if;end;$$;
create function pg_temp.denied(command text) returns void language plpgsql as $$
begin begin execute command;exception when insufficient_privilege then return;end;raise exception 'Expected denial: %',command;end;$$;
create function pg_temp.rejected(command text) returns void language plpgsql as $$
begin begin execute command;exception when sqlstate 'PT409' or serialization_failure or invalid_parameter_value or check_violation or not_null_violation then return;end;raise exception 'Expected rejection: %',command;end;$$;
create function pg_temp.payload(revision integer) returns jsonb language sql as $$
 select jsonb_build_object('id','e3780000-0000-4000-8000-000000000011','revision',revision,'display_name','Synthetic author',
 'title','Synthetic education story','body','Synthetic story body','theme','응원','emotion','따뜻함');$$;
create function pg_temp.submission(revision integer) returns jsonb language sql as $$
 select pg_temp.payload(revision)||jsonb_build_object('card_snapshot_id','e3780000-0000-4000-8000-000000000021',
 'publication_consent',true,'rights_consent',true,'consent_version','education-v1-2026-11-16');$$;
create function pg_temp.review(revision integer,status text) returns jsonb language sql as $$
 select pg_temp.payload(revision)||jsonb_build_object('card_snapshot_id','e3780000-0000-4000-8000-000000000021','status',status);$$;
insert into auth.users(id) values('e3780000-0000-4000-8000-000000000001'),('e3780000-0000-4000-8000-000000000002'),('e3780000-0000-4000-8000-000000000003');
insert into benchmark_private.oi_operators values('e3780000-0000-4000-8000-000000000003');
set local role anon;
select pg_temp.assert_true(public.oi_education_stories()='[]'::jsonb,'anonymous public list starts empty');
select pg_temp.denied($q$select * from benchmark_private.oi_education_stories$q$);
select pg_temp.denied($q$select public.oi_education_mutate('save',pg_temp.payload(0))$q$);
select pg_temp.denied($q$select public.oi_education_stories(0,24,true,false)$q$);
select pg_temp.rejected($q$select public.oi_education_stories(0,1000,false,false)$q$);
set local role authenticated;
select set_config('request.jwt.claim.sub','e3780000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(public.oi_education_mutate('save',pg_temp.payload(0))->>'status'='draft','no donation or location required');
select pg_temp.assert_true(jsonb_array_length(public.oi_education_stories(0,24,true,false))=1,'owner sees draft');
select pg_temp.assert_true(not exists(select 1 from public.oi_stories where id='e3780000-0000-4000-8000-000000000011'),'education never creates campus map story');
select pg_temp.rejected($q$select public.oi_education_mutate('save',pg_temp.payload(0))$q$);
select pg_temp.rejected($q$select public.oi_education_mutate('save',pg_temp.payload(1)||jsonb_build_object('body',repeat('가',501)))$q$);
select pg_temp.denied($q$select public.oi_education_stories(0,24,false,true)$q$);
select set_config('request.jwt.claim.sub','e3780000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true(public.oi_education_story('e3780000-0000-4000-8000-000000000011') is null,'other user cannot read draft');
select pg_temp.denied($q$select public.oi_education_mutate('save',pg_temp.payload(1))$q$);
select pg_temp.denied($q$insert into storage.objects(bucket_id,name,metadata) values('oi-story-media','e3780000-0000-4000-8000-000000000001/education/e3780000-0000-4000-8000-000000000011/photos/e3780000-0000-4000-8000-000000000031.jpg','{"mimetype":"image/jpeg","size":100}')$q$);
select set_config('request.jwt.claim.sub','e3780000-0000-4000-8000-000000000001',true);
insert into storage.objects(bucket_id,name,metadata) values('oi-story-media','e3780000-0000-4000-8000-000000000001/education/e3780000-0000-4000-8000-000000000011/photos/e3780000-0000-4000-8000-000000000031.jpg','{"mimetype":"image/jpeg","size":100}');
insert into storage.objects(bucket_id,name,metadata)
 select 'oi-story-media',path,'{"mimetype":"image/png","size":100}'::jsonb from unnest(array[
 'e3780000-0000-4000-8000-000000000001/education/e3780000-0000-4000-8000-000000000011/card/e3780000-0000-4000-8000-000000000021.png',
 'e3780000-0000-4000-8000-000000000001/education/e3780000-0000-4000-8000-000000000011/card/e3780000-0000-4000-8000-000000000021/back.png',
 'e3780000-0000-4000-8000-000000000001/education/e3780000-0000-4000-8000-000000000011/card/e3780000-0000-4000-8000-000000000021/front-preview.png',
 'e3780000-0000-4000-8000-000000000001/education/e3780000-0000-4000-8000-000000000011/card/e3780000-0000-4000-8000-000000000021/back-preview.png',
 'e3780000-0000-4000-8000-000000000001/education/e3780000-0000-4000-8000-000000000011/card/e3780000-0000-4000-8000-000000000099.png']) path;
select pg_temp.assert_true((public.oi_education_mutate('attach_media',pg_temp.payload(1)||jsonb_build_object('paths',array['e3780000-0000-4000-8000-000000000001/education/e3780000-0000-4000-8000-000000000011/photos/e3780000-0000-4000-8000-000000000031.jpg']))->>'revision')::int=2,'photo attachment advances revision');
select pg_temp.rejected($q$select public.oi_education_mutate('submit',pg_temp.submission(2)-'rights_consent')$q$);
select pg_temp.assert_true(public.oi_education_mutate('submit',pg_temp.submission(2))->>'status'='pending','consenting author submits both sides');
select pg_temp.denied($q$insert into storage.objects(bucket_id,name,metadata) values('oi-story-media','e3780000-0000-4000-8000-000000000001/education/e3780000-0000-4000-8000-000000000011/photos/e3780000-0000-4000-8000-000000000032.jpg','{"mimetype":"image/jpeg","size":100}')$q$);
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.assert_true(public.oi_education_story('e3780000-0000-4000-8000-000000000011') is null,'pending story not public');
select pg_temp.assert_true(not exists(select 1 from storage.objects where name like '%/education/%'),'pending pictures and cards not public');
set local role authenticated;
select set_config('request.jwt.claim.sub','e3780000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true(jsonb_array_length(public.oi_education_stories(0,24,false,true))=1,'operator can review pending story');
select pg_temp.rejected($q$select public.oi_education_mutate('review',pg_temp.review(3,'published')||jsonb_build_object('card_snapshot_id','e3780000-0000-4000-8000-000000000099'))$q$);
select pg_temp.assert_true(public.oi_education_mutate('review',pg_temp.review(3,'published'))->>'status'='published','operator approves current image set');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.assert_true(jsonb_array_length(public.oi_education_stories())=1,'published education story visible');
select pg_temp.assert_true(not(public.oi_education_story('e3780000-0000-4000-8000-000000000011')?'consent_version'),'private consent not exposed');
select pg_temp.assert_true(not(public.oi_education_story('e3780000-0000-4000-8000-000000000011')?'reports'),'private reports not exposed');
select pg_temp.assert_true((select count(*) from storage.objects where name like '%/education/%')=5,'only referenced photo and current four card images are public');
set local role authenticated;
select set_config('request.jwt.claim.sub','e3780000-0000-4000-8000-000000000002',true);
select public.oi_education_report('e3780000-0000-4000-8000-000000000011','privacy','Synthetic report');
select pg_temp.denied($q$select * from benchmark_private.oi_education_reports$q$);
select set_config('request.jwt.claim.sub','e3780000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(public.oi_education_mutate('reopen',pg_temp.payload(4))->>'status'='draft','reopening withdraws publication');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.assert_true(public.oi_education_stories()='[]'::jsonb,'reopen hides public story');
select pg_temp.assert_true(not exists(select 1 from storage.objects where name like '%/education/%'),'reopen hides public files');
reset role;
update benchmark_private.oi_story_creation_settings set unapproved_drafts_enabled=false where singleton;
set local role authenticated;
select set_config('request.jwt.claim.sub','e3780000-0000-4000-8000-000000000001',true);
select pg_temp.denied($q$select public.oi_education_mutate('save',pg_temp.payload(5))$q$);
select pg_temp.assert_true(public.oi_education_story('e3780000-0000-4000-8000-000000000011')->>'status'='draft','paused mode retains draft');
select pg_temp.assert_true((select count(*) from storage.objects where name like '%/education/%')=6,'paused mode retains owner files');
reset role;
update benchmark_private.oi_story_creation_settings set unapproved_drafts_enabled=true where singleton;
update benchmark_private.oi_account_members set account_id='e3780000-0000-4000-8000-000000000002' where auth_user_id='e3780000-0000-4000-8000-000000000001';
delete from public.oi_profiles where id='e3780000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','e3780000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true(public.oi_education_mutate('save',pg_temp.payload(5))->>'revision'='6','merged login retains education story after source profile is removed');
reset role;
insert into benchmark_private.oi_content_restrictions(member_id,note) values('e3780000-0000-4000-8000-000000000001','Synthetic restriction');
set local role authenticated;
select pg_temp.denied($q$select public.oi_education_mutate('save',pg_temp.payload(6))$q$);
reset role;
insert into benchmark_private.oi_account_deletions(account_id) values('e3780000-0000-4000-8000-000000000002');
set local role authenticated;
select pg_temp.assert_true(public.oi_education_story('e3780000-0000-4000-8000-000000000011') is null,'deleting account hides education story');
reset role;
delete from benchmark_private.oi_account_members where auth_user_id='e3780000-0000-4000-8000-000000000001';
insert into benchmark_private.oi_audit(actor_id,action,target_id) values('e3780000-0000-4000-8000-000000000003','campus:synthetic-audit','e3780000-0000-4000-8000-000000000011');
delete from auth.users where id='e3780000-0000-4000-8000-000000000001';
select pg_temp.assert_true(not exists(select 1 from benchmark_private.oi_education_stories where id='e3780000-0000-4000-8000-000000000011'),'Auth account deletion cascades education story');
select pg_temp.assert_true(not exists(select 1 from benchmark_private.oi_audit where target_id='e3780000-0000-4000-8000-000000000011' and action like 'education:%'),'education audit is cleaned with deleted story');
select pg_temp.assert_true(not exists(select 1 from benchmark_private.oi_education_reports where story_id='e3780000-0000-4000-8000-000000000011'),'education reports cascade with deleted story');
select pg_temp.assert_true(exists(select 1 from benchmark_private.oi_audit where target_id='e3780000-0000-4000-8000-000000000011' and action='campus:synthetic-audit'),'deleting education content preserves another channel audit with the same UUID');
rollback;
