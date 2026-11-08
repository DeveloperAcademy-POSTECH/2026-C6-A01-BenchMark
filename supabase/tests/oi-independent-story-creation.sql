-- Exercise the release policy through the RPCs and Storage permissions.
begin;
create function pg_temp.assert_true(result boolean, description text) returns void
language plpgsql as $$ begin
  if result is distinct from true then raise exception 'FAIL: %',description; end if;
end; $$;
create function pg_temp.assert_denied(command text) returns void
language plpgsql as $$ begin
  begin execute command;
  exception when insufficient_privilege then return; end;
  raise exception 'Expected permission denial: %',command;
end; $$;
create function pg_temp.draft(id uuid, revision integer) returns jsonb language sql as $$
  select jsonb_build_object('id',id,'revision',revision,'region_id','pond','title','Synthetic story',
    'body','Synthetic draft','theme','감사','emotion','기쁨','cucumber_name','테스트오이',
    'cucumber_asset','OiCats','card_asset','MYBlueCard',
    'latitude',36.01261057021347,'longitude',129.3197268697784);
$$;
create function pg_temp.evidence_review(id uuid, decision text) returns jsonb language sql as $$
  select jsonb_build_object('id',e.id,'status',decision,'review_note','Synthetic review',
    'expected_status',e.status,'expected_object_path',e.object_path,
    'expected_submitted_at',e.submitted_at,'expected_reviewed_at',e.reviewed_at)
  from public.oi_evidence_requests e where e.id=evidence_review.id;
$$;

insert into auth.users(id) values
 ('d2340000-0000-4000-8000-000000000001'),('d2340000-0000-4000-8000-000000000002'),('d2340000-0000-4000-8000-000000000003');
insert into benchmark_private.oi_operators values('d2340000-0000-4000-8000-000000000003');
insert into public.oi_evidence_requests(id,user_id,storage_owner_id,status,object_path,submitted_at,reviewed_at)
values
 ('d2340000-0000-4000-8000-000000000020','d2340000-0000-4000-8000-000000000002','d2340000-0000-4000-8000-000000000002','approved',
  'd2340000-0000-4000-8000-000000000002/d2340000-0000-4000-8000-000000000020/synthetic.png',now(),now()),
 ('d2340000-0000-4000-8000-000000000022','d2340000-0000-4000-8000-000000000002','d2340000-0000-4000-8000-000000000002','pending',
  'd2340000-0000-4000-8000-000000000002/d2340000-0000-4000-8000-000000000022/synthetic.png',now(),null);
insert into public.oi_writing_grants(id,evidence_id,user_id,story_limit) values
 ('d2340000-0000-4000-8000-000000000021','d2340000-0000-4000-8000-000000000020','d2340000-0000-4000-8000-000000000002',1);
insert into public.oi_stories(id,user_id,storage_owner_id,grant_id,region_id,title,body,theme,emotion,cucumber_name,cucumber_asset,card_asset,latitude,longitude,status)
values ('d2340000-0000-4000-8000-000000000012','d2340000-0000-4000-8000-000000000002','d2340000-0000-4000-8000-000000000002',
 'd2340000-0000-4000-8000-000000000021','pond','Existing story','Synthetic existing text','감사','기쁨','테스트오이','OiCats','MYBlueCard',
 36.01261057021347,129.3197268697784,'published');

set local role anon;
select pg_temp.assert_denied($q$select public.oi_mutate('save_story',pg_temp.draft('d2340000-0000-4000-8000-000000000011',0))$q$);
set local role authenticated;
select set_config('request.jwt.claim.sub','d2340000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(public.oi_capabilities()->>'unapproved_drafts_enabled'='true','writing opens by default');
select pg_temp.assert_true(public.oi_capabilities()->>'independent_story_creation'='true','client can verify independent writing policy');
select pg_temp.assert_true(not exists(select 1 from public.oi_evidence_requests),'writer has no evidence');
do $geometry$
declare
  invalid jsonb;
begin
  foreach invalid in array array['{"height_meters":"NaN"}'::jsonb,'{"heading_degrees":"Infinity"}'::jsonb]
  loop
    begin
      perform public.oi_mutate('save_story',pg_temp.draft('d2340000-0000-4000-8000-000000000011',0)||invalid);
      raise exception 'Accepted non-finite story placement: %',invalid;
    exception when invalid_parameter_value then null;
    end;
  end loop;
end; $geometry$;
select public.oi_mutate('save_story',pg_temp.draft('d2340000-0000-4000-8000-000000000011',0)
 ||'{"height_meters":1.35,"heading_degrees":263.5}');
select pg_temp.assert_true((select grant_id is null and status='draft' from public.oi_stories
 where id='d2340000-0000-4000-8000-000000000011'),'draft is independent of evidence');
insert into storage.objects(bucket_id,name) values
 ('oi-story-media','d2340000-0000-4000-8000-000000000001/d2340000-0000-4000-8000-000000000011/synthetic.png');
select public.oi_mutate('attach_media','{"id":"d2340000-0000-4000-8000-000000000011","revision":1,"paths":["d2340000-0000-4000-8000-000000000001/d2340000-0000-4000-8000-000000000011/synthetic.png"]}');
select public.oi_mutate('submit_story','{"id":"d2340000-0000-4000-8000-000000000011","revision":2}');
select pg_temp.assert_denied($q$select public.oi_mutate('review_story','{"id":"d2340000-0000-4000-8000-000000000011","revision":3,"status":"published"}')$q$);

select set_config('request.jwt.claim.sub','d2340000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true(not exists(select 1 from public.oi_stories where id='d2340000-0000-4000-8000-000000000011'),'pending story is private');
select pg_temp.assert_denied($q$select public.oi_mutate('reopen_story','{"id":"d2340000-0000-4000-8000-000000000011","revision":3}')$q$);
select pg_temp.assert_denied($q$select public.oi_review_evidence(pg_temp.evidence_review('d2340000-0000-4000-8000-000000000022','approved'))$q$);

select set_config('request.jwt.claim.sub','d2340000-0000-4000-8000-000000000003',true);
select public.oi_set_unapproved_drafts(false);
select pg_temp.assert_denied($q$select public.oi_mutate('review_story','{"id":"d2340000-0000-4000-8000-000000000011","revision":3,"status":"published"}')$q$);
select set_config('request.jwt.claim.sub','d2340000-0000-4000-8000-000000000002',true);
select pg_temp.assert_denied($q$select public.oi_mutate('save_story',
 pg_temp.draft('d2340000-0000-4000-8000-000000000013',0)||'{"grant_id":"d2340000-0000-4000-8000-000000000021"}')$q$);
select set_config('request.jwt.claim.sub','d2340000-0000-4000-8000-000000000003',true);
select public.oi_set_unapproved_drafts(true);
select public.oi_mutate('review_story','{"id":"d2340000-0000-4000-8000-000000000011","revision":3,"status":"published"}');
select public.oi_review_evidence(pg_temp.evidence_review('d2340000-0000-4000-8000-000000000022','approved'));
select pg_temp.assert_true(not exists(select 1 from public.oi_writing_grants
 where evidence_id='d2340000-0000-4000-8000-000000000022'),'evidence review gives no writing grant');
select public.oi_review_evidence(pg_temp.evidence_review('d2340000-0000-4000-8000-000000000020','revoked'));
select pg_temp.assert_true((select status='published' and revision=1 and title='Existing story' from public.oi_stories
 where id='d2340000-0000-4000-8000-000000000012'),'revoking evidence leaves the existing story intact');
select pg_temp.assert_true((select revoked_at is not null from public.oi_writing_grants
 where id='d2340000-0000-4000-8000-000000000021'),'legacy grant history is preserved');

select set_config('request.jwt.claim.sub','d2340000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true((select status='published' and height_meters=1.35 and heading_degrees=263.5 from public.oi_stories
 where id='d2340000-0000-4000-8000-000000000011'),'publication preserves the author placement sent to AR');
select public.oi_mutate('save_story',pg_temp.draft('d2340000-0000-4000-8000-000000000013',0)
 ||'{"grant_id":"d2340000-0000-4000-8000-000000000021"}');
select pg_temp.assert_true((select grant_id is null from public.oi_stories
 where id='d2340000-0000-4000-8000-000000000013'),'old clients cannot link a new draft to a grant');
select public.oi_mutate('reopen_story','{"id":"d2340000-0000-4000-8000-000000000012","revision":1}');
select public.oi_mutate('save_story',pg_temp.draft('d2340000-0000-4000-8000-000000000012',2));
select pg_temp.assert_true((select status='draft' and grant_id='d2340000-0000-4000-8000-000000000021' from public.oi_stories
 where id='d2340000-0000-4000-8000-000000000012'),'legacy stories can be edited without changing the historical link');
rollback;
