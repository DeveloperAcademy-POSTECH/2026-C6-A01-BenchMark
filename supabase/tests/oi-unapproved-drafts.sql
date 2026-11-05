-- Synthetic data only. Exercise policy transitions through the actual RPC/RLS paths.
begin;
create function pg_temp.assert_true(result boolean, description text) returns void
language plpgsql as $$ begin
  if result is distinct from true then raise exception 'FAIL: %',description; end if;
end; $$;
create function pg_temp.assert_error(command text, expected_state text) returns void
language plpgsql as $$ begin
  begin execute command;
  exception when others then
    if sqlstate=expected_state then return; end if;
    raise exception 'Unexpected SQLSTATE %, expected %, command %',sqlstate,expected_state,command;
  end;
  raise exception 'Expected error % for %',expected_state,command;
end; $$;
create function pg_temp.draft(id uuid, revision integer) returns jsonb language sql as $$
  select jsonb_build_object('id',id,'revision',revision,'region_id','pond','title','Temporary story',
    'body','Synthetic body preserved when policy changes','theme','감사','emotion','기쁨',
    'cucumber_name','테스트오이','cucumber_asset','OiCats','card_asset','MYBlueCard',
    'latitude',36.01261057021347,'longitude',129.3197268697784);
$$;
insert into auth.users(id) values
 ('d1000000-0000-4000-8000-000000000001'),('d1000000-0000-4000-8000-000000000002'),('d1000000-0000-4000-8000-000000000003');
insert into benchmark_private.oi_operators values('d1000000-0000-4000-8000-000000000003');
set local role anon;
select pg_temp.assert_error('select public.oi_set_unapproved_drafts(true)','42501');
select pg_temp.assert_error($q$select public.oi_mutate('save_story',pg_temp.draft('d1000000-0000-4000-8000-000000000011',0))$q$,'42501');
set local role authenticated;
select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(public.oi_capabilities()->>'unapproved_drafts_enabled'='false','default closed');
select pg_temp.assert_true(public.oi_capabilities()->>'school_profile_enabled'='true'
  and public.oi_capabilities()->>'farmer_outfit_enabled'='true','independent capabilities survive integration');
select pg_temp.assert_error('select public.oi_set_unapproved_drafts(true)','42501');
select pg_temp.assert_error('update benchmark_private.oi_story_creation_settings set unapproved_drafts_enabled=true','42501');
select pg_temp.assert_error($q$select public.oi_mutate('save_story',pg_temp.draft('d1000000-0000-4000-8000-000000000011',0))$q$,'42501');
select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-000000000003',true);
select public.oi_set_unapproved_drafts(true);
select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(public.oi_capabilities()->>'unapproved_drafts_enabled'='true','enabled capability');
select public.oi_mutate('save_story',pg_temp.draft('d1000000-0000-4000-8000-000000000011',0));
select public.oi_mutate('save_story',pg_temp.draft('d1000000-0000-4000-8000-000000000012',0));
select public.oi_mutate('save_story',pg_temp.draft('d1000000-0000-4000-8000-000000000013',0));
select pg_temp.assert_true((select count(*)=3 from public.oi_stories where grant_id is null and status='draft'),'real draft rows without grants');
select pg_temp.assert_true((select count(*)=0 from public.oi_writing_grants),'no synthetic grants');
select pg_temp.assert_true((select count(*)=0 from public.oi_evidence_requests),'no synthetic evidence');
insert into storage.objects(bucket_id,name) values('oi-story-media','d1000000-0000-4000-8000-000000000001/d1000000-0000-4000-8000-000000000011/photo.jpg');
select public.oi_mutate('attach_media','{"id":"d1000000-0000-4000-8000-000000000011","revision":1,"paths":["d1000000-0000-4000-8000-000000000001/d1000000-0000-4000-8000-000000000011/photo.jpg"]}');
select public.oi_mutate('submit_story','{"id":"d1000000-0000-4000-8000-000000000012","revision":1}');
select public.oi_mutate('submit_story','{"id":"d1000000-0000-4000-8000-000000000013","revision":1}');
select pg_temp.assert_error($q$select public.oi_mutate('review_story','{"id":"d1000000-0000-4000-8000-000000000013","revision":2,"status":"published"}')$q$,'42501');
select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true((select count(*)=0 from public.oi_stories),'others cannot read drafts');
select pg_temp.assert_true((select count(*)=0 from storage.objects where bucket_id='oi-story-media'),'photos private');
select pg_temp.assert_error($q$select public.oi_mutate('save_story',pg_temp.draft('d1000000-0000-4000-8000-000000000011',2))$q$,'42501');
select pg_temp.assert_error($q$insert into storage.objects(bucket_id,name) values('oi-story-media','d1000000-0000-4000-8000-000000000001/d1000000-0000-4000-8000-000000000011/foreign.jpg')$q$,'42501');
select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-000000000003',true);
select public.oi_mutate('review_story','{"id":"d1000000-0000-4000-8000-000000000013","revision":2,"status":"published"}');
select public.oi_set_unapproved_drafts(false);
select pg_temp.assert_error($q$select public.oi_mutate('review_story','{"id":"d1000000-0000-4000-8000-000000000012","revision":2,"status":"published"}')$q$,'42501');
select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(public.oi_capabilities()->>'unapproved_drafts_enabled'='false','disabled capability');
select pg_temp.assert_true((select count(*)=3 from public.oi_stories),'all stories retained');
select pg_temp.assert_true((select count(*)=1 from public.oi_story_media),'media association retained');
select pg_temp.assert_true((select count(*)=1 from storage.objects where bucket_id='oi-story-media'),'original photo still readable');
select pg_temp.assert_true((select status='published' from public.oi_stories where id='d1000000-0000-4000-8000-000000000013'),'published status unchanged');
select pg_temp.assert_error($q$select public.oi_mutate('save_story',pg_temp.draft('d1000000-0000-4000-8000-000000000011',2))$q$,'42501');
select pg_temp.assert_error($q$select public.oi_mutate('save_story',pg_temp.draft('d1000000-0000-4000-8000-000000000014',0))$q$,'42501');
select pg_temp.assert_error($q$select public.oi_mutate('submit_story','{"id":"d1000000-0000-4000-8000-000000000011","revision":2}')$q$,'42501');
select pg_temp.assert_error($q$select public.oi_mutate('attach_media','{"id":"d1000000-0000-4000-8000-000000000011","revision":2,"paths":[]}')$q$,'42501');
select pg_temp.assert_error($q$insert into storage.objects(bucket_id,name) values('oi-story-media','d1000000-0000-4000-8000-000000000001/d1000000-0000-4000-8000-000000000011/after-off.jpg')$q$,'42501');
select public.oi_mutate('reopen_story','{"id":"d1000000-0000-4000-8000-000000000012","revision":2}');
-- A real approval can be linked to an existing temporary draft without replacing its files.
reset role;
insert into public.oi_evidence_requests(id,user_id,storage_owner_id,status) values
 ('d1000000-0000-4000-8000-000000000021','d1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','approved');
insert into public.oi_writing_grants(id,evidence_id,user_id,story_limit) values
 ('d1000000-0000-4000-8000-000000000022','d1000000-0000-4000-8000-000000000021','d1000000-0000-4000-8000-000000000001',1);
set local role authenticated;
select public.oi_mutate('save_story',pg_temp.draft('d1000000-0000-4000-8000-000000000011',2)||'{"grant_id":"d1000000-0000-4000-8000-000000000022"}');
select pg_temp.assert_true((select grant_id is not null and revision=3 from public.oi_stories where id='d1000000-0000-4000-8000-000000000011'),'approval attached to same draft');
select pg_temp.assert_true((select count(*)=1 from public.oi_story_media),'photo retained on approval');
select pg_temp.assert_error($q$select public.oi_mutate('save_story',pg_temp.draft('d1000000-0000-4000-8000-000000000012',3)||'{"grant_id":"d1000000-0000-4000-8000-000000000022"}')$q$,'42501');
select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-000000000003',true);
select public.oi_set_unapproved_drafts(true);
select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-000000000001',true);
select pg_temp.assert_error($q$select public.oi_mutate('save_story',pg_temp.draft('d1000000-0000-4000-8000-000000000011',3))$q$,'42501');
reset role;
update public.oi_writing_grants set revoked_at=now() where id='d1000000-0000-4000-8000-000000000022';
set local role authenticated;
select pg_temp.assert_error($q$select public.oi_mutate('save_story',pg_temp.draft('d1000000-0000-4000-8000-000000000011',3)||'{"grant_id":"d1000000-0000-4000-8000-000000000022"}')$q$,'42501');
select pg_temp.assert_error($q$insert into storage.objects(bucket_id,name) values('oi-story-media','d1000000-0000-4000-8000-000000000001/d1000000-0000-4000-8000-000000000011/revoked.jpg')$q$,'42501');
rollback;
