begin;
create function pg_temp.assert_true(value boolean,label text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception 'Assertion failed: %',label; end if; end; $$;
create function pg_temp.assert_error(command text,expected text) returns void language plpgsql as $$
begin
  begin execute command; exception when others then
    if sqlstate=expected then return; end if;
    raise exception 'Expected %, got %: %',expected,sqlstate,sqlerrm;
  end;
  raise exception 'Expected an error: %',expected;
end; $$;
insert into auth.users(id) values
 ('a1000000-0000-4000-8000-000000000001'),('a1000000-0000-4000-8000-000000000002'),
 ('a1000000-0000-4000-8000-000000000003'),('a1000000-0000-4000-8000-000000000004'),('a1000000-0000-4000-8000-000000000005');
insert into auth.identities(user_id,provider) values
 ('a1000000-0000-4000-8000-000000000001','google'),('a1000000-0000-4000-8000-000000000002','apple'),
 ('a1000000-0000-4000-8000-000000000004','google'),('a1000000-0000-4000-8000-000000000005','apple');
update public.oi_profiles set nickname='Target farmer',school_id='postech' where id='a1000000-0000-4000-8000-000000000001';
update public.oi_profiles set nickname='Source farmer' where id='a1000000-0000-4000-8000-000000000002';
insert into benchmark_private.oi_operators values('a1000000-0000-4000-8000-000000000003');
insert into auth.sessions(id,user_id,created_at) values
 ('b1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001',now()-interval '30 seconds'),
 ('b1000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000002',now()-interval '20 seconds'),
 ('b1000000-0000-4000-8000-000000000003','a1000000-0000-4000-8000-000000000003',now()-interval '20 seconds'),
 ('b1000000-0000-4000-8000-000000000005','a1000000-0000-4000-8000-000000000005',now()-interval '20 seconds'),
 ('b1000000-0000-4000-8000-000000000011','a1000000-0000-4000-8000-000000000001',now()-interval '1 day'),
 ('b1000000-0000-4000-8000-000000000012','a1000000-0000-4000-8000-000000000002',now()-interval '1 day'),
 ('b1000000-0000-4000-8000-000000000013','a1000000-0000-4000-8000-000000000002',now()-interval '1 second');
insert into public.oi_evidence_requests(id,user_id,storage_owner_id,status,object_path) values
 ('e1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','approved','a1000000-0000-4000-8000-000000000001/e1000000-0000-4000-8000-000000000001/target.pdf'),
 ('e1000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000002','approved','a1000000-0000-4000-8000-000000000002/e1000000-0000-4000-8000-000000000002/source.pdf'),
 ('e1000000-0000-4000-8000-000000000003','a1000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000002','revoked','a1000000-0000-4000-8000-000000000002/e1000000-0000-4000-8000-000000000003/revoked.pdf');
insert into public.oi_writing_grants(id,evidence_id,user_id,story_limit,revoked_at) values
 ('f1000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001',5,null),
 ('f1000000-0000-4000-8000-000000000002','e1000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000002',5,null),
 ('f1000000-0000-4000-8000-000000000003','e1000000-0000-4000-8000-000000000003','a1000000-0000-4000-8000-000000000002',2,now());
insert into public.oi_stories(id,user_id,storage_owner_id,grant_id,region_id,title,body,theme,emotion,cucumber_name,cucumber_asset,card_asset,latitude,longitude,status)
 select ('c1000000-0000-4000-8000-00000000000'||n)::uuid,
  case when n=1 then 'a1000000-0000-4000-8000-000000000001'::uuid else 'a1000000-0000-4000-8000-000000000002'::uuid end,
  case when n=1 then 'a1000000-0000-4000-8000-000000000001'::uuid else 'a1000000-0000-4000-8000-000000000002'::uuid end,
  case when n=1 then 'f1000000-0000-4000-8000-000000000001'::uuid when n in(3,4) then 'f1000000-0000-4000-8000-000000000003'::uuid else 'f1000000-0000-4000-8000-000000000002'::uuid end,
  'pond','Synthetic title','Synthetic body','감사','기쁨','Synthetic cucumber','OiCats','MYBasicCard',36.01261057021347,129.3197268697784,
  case when n in(1,2) then 'published' when n=3 then 'hidden' when n=4 then 'deleted' else 'draft' end
 from generate_series(1,5)n;
insert into public.oi_story_media(story_id,object_path,position) values
 ('c1000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000002/c1000000-0000-4000-8000-000000000002/photo.jpg',0);
insert into storage.objects(bucket_id,name,owner_id) values
 ('oi-evidence','a1000000-0000-4000-8000-000000000002/e1000000-0000-4000-8000-000000000002/source.pdf','a1000000-0000-4000-8000-000000000002'),
 ('oi-story-media','a1000000-0000-4000-8000-000000000002/c1000000-0000-4000-8000-000000000002/photo.jpg','a1000000-0000-4000-8000-000000000002'),
 ('oi-story-media','a1000000-0000-4000-8000-000000000002/c1000000-0000-4000-8000-000000000005/staged.jpg','a1000000-0000-4000-8000-000000000002');
insert into public.oi_collections values
 ('a1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','2026-10-03'),
 ('a1000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000001','2026-10-01'),
 ('a1000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000002','2026-10-02');
insert into public.oi_favorites select * from public.oi_collections;

set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"session_id":"b1000000-0000-4000-8000-000000000001"}',true);
select pg_temp.assert_true(public.oi_capabilities()->>'account_id'='a1000000-0000-4000-8000-000000000001','unmerged context remains compatible');
select pg_temp.assert_error($q$select public.oi_merge_accounts('preview','d1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000002','b1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000002')$q$,'42501');
select pg_temp.assert_error('select * from benchmark_private.oi_merge_operations','42501');
reset role;
set local role service_role;
select pg_temp.assert_error($q$select public.oi_merge_accounts(null,'d1000000-0000-4000-8000-000000000009','a1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000002','b1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000002')$q$,'22023');
select public.oi_merge_accounts('preview','d1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000002','b1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000002') as preview \gset
select pg_temp.assert_true((:'preview'::jsonb->'counts')='{"stories":5,"collections":2,"favorites":2,"evidence":3,"grants":3}'::jsonb,'preview counts union duplicates');
select pg_temp.assert_error(format($q$select public.oi_merge_accounts('confirm','d1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000002','b1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000002',%L,false)$q$,:'preview'::jsonb->>'challenge_id'),'22023');
select pg_temp.assert_error($q$select public.oi_merge_accounts('preview','d1000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000003','b1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000003')$q$,'42501');
select public.oi_merge_accounts('confirm','d1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000002','b1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000002',(:'preview'::jsonb->>'challenge_id')::uuid,true) as receipt \gset
select pg_temp.assert_true((:'receipt'::jsonb->>'already_merged')::boolean=false,'first receipt not replay');
select pg_temp.assert_true((public.oi_merge_accounts('confirm','d1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000002','b1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000002',(:'preview'::jsonb->>'challenge_id')::uuid,true)->>'already_merged')::boolean,'same operation returns receipt');
select pg_temp.assert_error($q$select public.oi_merge_accounts('confirm','d1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000002','b1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001',true)$q$,'42501');
reset role;
select pg_temp.assert_true((select count(*)=5 and bool_and(user_id='a1000000-0000-4000-8000-000000000001') from public.oi_stories),'all story ownership transferred');
select pg_temp.assert_true((select array_agg(status order by id)=array['published','published','hidden','deleted','draft'] from public.oi_stories),'story statuses preserved');
select pg_temp.assert_true((select nickname='Target farmer' and school_id='postech' from public.oi_profiles where id='a1000000-0000-4000-8000-000000000001'),'target profile wins');
select pg_temp.assert_true((select count(*)=2 from public.oi_collections),'collection union');
select pg_temp.assert_true((select count(*)=2 from public.oi_favorites),'favorite union');
select pg_temp.assert_true((select min(created_at)='2026-10-01'::timestamptz from public.oi_collections),'earliest collection date preserved');
select pg_temp.assert_true((select count(*)=3 and count(*)filter(where revoked_at is not null)=1 from public.oi_writing_grants),'grants and revocation preserved');
select pg_temp.assert_true((select array_agg(status order by id)=array['approved','approved','revoked'] from public.oi_evidence_requests),'evidence statuses preserved');
select pg_temp.assert_true((select count(*)=5 from auth.users),'no Auth users deleted');
select pg_temp.assert_true((select count(*)=3 and bool_and(owner_id='a1000000-0000-4000-8000-000000000002') from storage.objects),'Storage objects and owners unchanged');
select pg_temp.assert_error($q$delete from auth.users where id='a1000000-0000-4000-8000-000000000002'$q$,'23503');

set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"session_id":"b1000000-0000-4000-8000-000000000002"}',true);
select pg_temp.assert_true(public.oi_capabilities()->>'account_id'='a1000000-0000-4000-8000-000000000001','source proof resolves canonical account');
select pg_temp.assert_true(jsonb_array_length(public.oi_capabilities()->'account_member_ids')=2,'local recovery membership context');
select pg_temp.assert_true(public.oi_capabilities()->'account_providers'='["apple","google"]'::jsonb,'verified group provider labels');
select pg_temp.assert_error('select * from auth.identities','42501');
select pg_temp.assert_true((select count(*)=3 from public.oi_evidence_requests),'source proof sees unified private evidence');
select pg_temp.assert_true((select count(*)=3 from storage.objects),'source proof reads original-prefix media and evidence');
select set_config('request.jwt.claims','{"session_id":"b1000000-0000-4000-8000-000000000012","iat":9999999999}',true);
select pg_temp.assert_error('select public.oi_account_context()','PT401');
select pg_temp.assert_true((select count(*)=0 from public.oi_evidence_requests),'old refreshed source session cannot read evidence');
select pg_temp.assert_true((select count(*)=1 from storage.objects),'old source session only sees published media');
select set_config('request.jwt.claims','{"session_id":"b1000000-0000-4000-8000-000000000013"}',true);
select pg_temp.assert_error('select public.oi_account_context()','PT401');
reset role;
insert into auth.sessions(id,user_id,created_at) values('b1000000-0000-4000-8000-000000000014','a1000000-0000-4000-8000-000000000002',clock_timestamp());
set local role authenticated;
select set_config('request.jwt.claims','{"session_id":"b1000000-0000-4000-8000-000000000014"}',true);
select pg_temp.assert_true(public.oi_account_context()->>'id'='a1000000-0000-4000-8000-000000000001','new post-cutover session works');
select public.oi_mutate('reopen_story','{"id":"c1000000-0000-4000-8000-000000000002","revision":1}');
insert into storage.objects(bucket_id,name) values('oi-story-media','a1000000-0000-4000-8000-000000000002/c1000000-0000-4000-8000-000000000002/new.jpg');
select public.oi_mutate('attach_media','{"id":"c1000000-0000-4000-8000-000000000002","revision":2,"paths":["a1000000-0000-4000-8000-000000000002/c1000000-0000-4000-8000-000000000002/new.jpg"]}');
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{}',true);
select pg_temp.assert_true((select count(*)=0 from public.oi_evidence_requests),'unrelated account cannot read merged evidence');
select pg_temp.assert_true(public.oi_capabilities()->'account_providers'='["google"]'::jsonb,'unrelated caller receives only its own provider label');
select pg_temp.assert_true((select count(*)=0 from storage.objects where bucket_id='oi-evidence'),'unrelated account cannot read original evidence paths');
select pg_temp.assert_error($q$insert into storage.objects(bucket_id,name) values('oi-story-media','a1000000-0000-4000-8000-000000000002/c1000000-0000-4000-8000-000000000002/attack.jpg')$q$,'42501');
reset role;

set local role service_role;
select public.oi_merge_accounts('preview','d1000000-0000-4000-8000-000000000003','a1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000005','b1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000005') as expiring \gset
reset role;
update benchmark_private.oi_merge_operations set expires_at=now()-interval '1 second' where operation_id='d1000000-0000-4000-8000-000000000003';
set local role service_role;
select pg_temp.assert_error(format($q$select public.oi_merge_accounts('confirm','d1000000-0000-4000-8000-000000000003','a1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000005','b1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000005',%L,true)$q$,:'expiring'::jsonb->>'challenge_id'),'40001');
reset role;
select pg_temp.assert_true((select account_id=auth_user_id from benchmark_private.oi_account_members where auth_user_id='a1000000-0000-4000-8000-000000000005'),'expired operation changes nothing');
insert into public.oi_evidence_requests(id,user_id,storage_owner_id,status)
values('e1000000-0000-4000-8000-000000000005','a1000000-0000-4000-8000-000000000005','a1000000-0000-4000-8000-000000000005','pending');
insert into public.oi_collections values('a1000000-0000-4000-8000-000000000005','c1000000-0000-4000-8000-000000000001','2026-09-01');
set local role service_role;
select public.oi_merge_accounts('preview','d1000000-0000-4000-8000-000000000004','a1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000005','b1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000005') as failing \gset
reset role;
create function pg_temp.fail_merge_write() returns trigger language plpgsql as $$ begin raise exception 'Synthetic storage failure'; end; $$;
create trigger fail_merge_write before update on public.oi_evidence_requests for each row
when(old.user_id='a1000000-0000-4000-8000-000000000005') execute function pg_temp.fail_merge_write();
set local role service_role;
select pg_temp.assert_error(format($q$select public.oi_merge_accounts('confirm','d1000000-0000-4000-8000-000000000004','a1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000005','b1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000005',%L,true)$q$,:'failing'::jsonb->>'challenge_id'),'P0001');
reset role;
select pg_temp.assert_true((select account_id=auth_user_id from benchmark_private.oi_account_members where auth_user_id='a1000000-0000-4000-8000-000000000005'),'failed commit preserves membership');
select pg_temp.assert_true((select created_at='2026-10-01'::timestamptz from public.oi_collections where user_id='a1000000-0000-4000-8000-000000000001' and story_id='c1000000-0000-4000-8000-000000000001'),'failed commit rolls back earlier union updates');
select pg_temp.assert_true((select consumed_at is null from benchmark_private.oi_merge_operations where operation_id='d1000000-0000-4000-8000-000000000004'),'failed transaction does not consume challenge');
drop trigger fail_merge_write on public.oi_evidence_requests;

-- One provider proof can classify a newly created blank account without bypassing review/consent.
insert into auth.users(id,created_at) values
 ('a1000000-0000-4000-8000-000000000006',now()-interval '30 seconds'),
 ('a1000000-0000-4000-8000-000000000007',now()-interval '2 days'),
 ('a1000000-0000-4000-8000-000000000008',now()-interval '10 seconds'),
 ('a1000000-0000-4000-8000-000000000009',now()-interval '2 days');
update public.oi_profiles set nickname='Existing custom profile' where id='a1000000-0000-4000-8000-000000000008';
insert into auth.sessions(id,user_id,created_at) values
 ('b1000000-0000-4000-8000-000000000006','a1000000-0000-4000-8000-000000000006',now()-interval '1 second'),
 ('b1000000-0000-4000-8000-000000000007','a1000000-0000-4000-8000-000000000007',now()-interval '1 second'),
 ('b1000000-0000-4000-8000-000000000008','a1000000-0000-4000-8000-000000000008',now()-interval '10 seconds'),
 ('b1000000-0000-4000-8000-000000000009','a1000000-0000-4000-8000-000000000009',now()-interval '1 second');
set local role service_role;
select public.oi_merge_accounts('preview','d1000000-0000-4000-8000-000000000006','a1000000-0000-4000-8000-000000000009','a1000000-0000-4000-8000-000000000006','b1000000-0000-4000-8000-000000000009','b1000000-0000-4000-8000-000000000006') as fresh \gset
select pg_temp.assert_true((:'fresh'::jsonb->>'source_is_new')::boolean,'delayed PKCE first-session blank source is add-method candidate');
reset role;
insert into auth.sessions(id,user_id,created_at) values
 ('b1000000-0000-4000-8000-000000000016','a1000000-0000-4000-8000-000000000006',now()-interval '5 seconds');
set local role service_role;
select pg_temp.assert_true((public.oi_merge_accounts('preview','d1000000-0000-4000-8000-000000000006','a1000000-0000-4000-8000-000000000009','a1000000-0000-4000-8000-000000000006','b1000000-0000-4000-8000-000000000009','b1000000-0000-4000-8000-000000000006')->>'source_is_new')::boolean=false,'another earlier session forces existing-account review');
reset role;
delete from auth.sessions where id='b1000000-0000-4000-8000-000000000016';
set local role service_role;
select public.oi_merge_accounts('preview','d1000000-0000-4000-8000-000000000006','a1000000-0000-4000-8000-000000000009','a1000000-0000-4000-8000-000000000006','b1000000-0000-4000-8000-000000000009','b1000000-0000-4000-8000-000000000006') as fresh \gset

select pg_temp.assert_true((public.oi_merge_accounts('preview','d1000000-0000-4000-8000-000000000007','a1000000-0000-4000-8000-000000000009','a1000000-0000-4000-8000-000000000007','b1000000-0000-4000-8000-000000000009','b1000000-0000-4000-8000-000000000007')->>'source_is_new')::boolean=false,'old Auth user is existing account');
select pg_temp.assert_true((public.oi_merge_accounts('preview','d1000000-0000-4000-8000-000000000008','a1000000-0000-4000-8000-000000000009','a1000000-0000-4000-8000-000000000008','b1000000-0000-4000-8000-000000000009','b1000000-0000-4000-8000-000000000008')->>'source_is_new')::boolean=false,'custom profile is existing account');
reset role;
update public.oi_profiles set nickname='Changed after preview' where id='a1000000-0000-4000-8000-000000000006';
set local role service_role;
select pg_temp.assert_error(format($q$select public.oi_merge_accounts('confirm','d1000000-0000-4000-8000-000000000006','a1000000-0000-4000-8000-000000000009','a1000000-0000-4000-8000-000000000006','b1000000-0000-4000-8000-000000000009','b1000000-0000-4000-8000-000000000006',%L,true)$q$,:'fresh'::jsonb->>'challenge_id'),'40001');
select pg_temp.assert_true((public.oi_merge_accounts('preview','d1000000-0000-4000-8000-000000000006','a1000000-0000-4000-8000-000000000009','a1000000-0000-4000-8000-000000000006','b1000000-0000-4000-8000-000000000009','b1000000-0000-4000-8000-000000000006')->>'source_is_new')::boolean=false,'same proof can refresh preview into existing-account review without reauthentication');
reset role;
rollback;
