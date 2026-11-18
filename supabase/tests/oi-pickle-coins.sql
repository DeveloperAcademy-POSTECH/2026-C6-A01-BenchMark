\set ON_ERROR_STOP on
begin;
create function pg_temp.check_coin(value boolean,label text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception 'Coin assertion failed: %',label; end if; end; $$;
create function pg_temp.coin_error(command text,expected text) returns void language plpgsql as $$
begin
  begin execute command; exception when others then
    if sqlstate=expected then return; end if;
    raise exception 'Expected %, got %: %',expected,sqlstate,sqlerrm;
  end;
  raise exception 'Expected error: %',expected;
end; $$;
\set owner 'f5060000-0000-4000-8000-000000000004'
\set unlimited 'f5060000-0000-4000-8000-000000000005'
\set proof 'f5060000-0000-4000-8000-000000000006'
\set source 'f5060000-0000-4000-8000-000000000007'
\set session 'f5060000-0000-4000-8000-000000000014'
\set unlimited_session 'f5060000-0000-4000-8000-000000000015'
\set proof_session 'f5060000-0000-4000-8000-000000000016'
\set source_session 'f5060000-0000-4000-8000-000000000017'
\set old_story 'f5060000-0000-4000-8000-000000000101'
\set story 'f5060000-0000-4000-8000-000000000103'
\set certificate 'f5060000-0000-4000-8000-000000000301'
select pg_temp.check_coin((select balance=40 from benchmark_private.oi_pickle_wallets where account_id='f5060000-0000-4000-8000-000000000002'),'existing account signup and one approved certificate');
select pg_temp.check_coin((select balance=10 from benchmark_private.oi_pickle_wallets where account_id='f5060000-0000-4000-8000-000000000003'),'duplicate approved certificate not paid twice');
select pg_temp.check_coin((select count(*)=1 from benchmark_private.oi_coin_certificate_claims),'one historical distinct certificate claim');
select pg_temp.check_coin((select cost=0 from benchmark_private.oi_pickle_plant_receipts where story_id=:'old_story'),'old public story is free');
select pg_temp.check_coin((select not credited from benchmark_private.oi_pickle_collection_rewards where account_id='f5060000-0000-4000-8000-000000000002' and story_id=:'old_story'),'past collection seeded without reward');
select pg_temp.check_coin((select count(*)=1 from benchmark_private.oi_farmer_owned_items where account_id='f5060000-0000-4000-8000-000000000001'),'only currently worn catalogue item grandfathered');
insert into auth.users(id) values(:'owner'),(:'unlimited'),(:'proof'),(:'source');
insert into auth.sessions(id,user_id) values(:'session',:'owner'),(:'unlimited_session',:'unlimited'),(:'proof_session',:'proof'),(:'source_session',:'source');
select pg_temp.check_coin(not exists(select 1 from benchmark_private.oi_pickle_wallets where account_id=:'owner'),'new identity does not mint coins before canonical usage');
insert into benchmark_private.oi_pickle_unlimited_accounts values(:'unlimited');
set local role anon;
select pg_temp.coin_error('select public.oi_pickle_wallet()','42501');
set local role authenticated;
select set_config('request.jwt.claim.sub',:'owner',true);
select pg_temp.check_coin((public.oi_pickle_wallet()->>'balance')::integer=10,'new account welcome10');
select pg_temp.check_coin((public.oi_pickle_wallet()->>'balance')::integer=10,'welcome replay does not mint');
select pg_temp.coin_error('select * from benchmark_private.oi_pickle_wallets','42501');
select pg_temp.coin_error('select benchmark_private.oi_pickle_apply(auth.uid(),''forged'',''certificate'',30)','42501');
select pg_temp.coin_error('select public.oi_prepare_coin_evidence(null,null,null)','42501');
select public.oi_mutate('collect',jsonb_build_object('id',:'old_story')) as collected \gset
select pg_temp.check_coin(:'collected'::jsonb @> '{"coin_reward":1,"wallet":{"balance":11}}','new other story collection earns1');
select pg_temp.check_coin(public.oi_mutate('collect',jsonb_build_object('id',:'old_story'))->'coin_reward'='0'::jsonb,'repeat collect does not pay');
select public.oi_mutate('remove_collection',jsonb_build_object('id',:'old_story'));
select pg_temp.check_coin(public.oi_mutate('collect',jsonb_build_object('id',:'old_story'))->'coin_reward'='0'::jsonb,'remove/recollect does not pay');
select set_config('request.jwt.claim.sub','f5060000-0000-4000-8000-000000000002',true);
select public.oi_mutate('remove_collection',jsonb_build_object('id',:'old_story'));
select pg_temp.check_coin(public.oi_mutate('collect',jsonb_build_object('id',:'old_story'))->'coin_reward'='0'::jsonb,'past collection cannot replay for reward');
select set_config('request.jwt.claim.sub','f5060000-0000-4000-8000-000000000001',true);
select pg_temp.check_coin(public.oi_mutate('collect',jsonb_build_object('id',:'old_story'))->'coin_reward'='0'::jsonb,'own story gives no reward');
select public.oi_save_farmer_outfit('{"version":1,"character":"kyu","slots":{"top":"kyu-3916-2673"}}');
select public.oi_save_farmer_outfit('{"version":1,"character":"kyu","slots":{"set":"legacy-classic"}}');
select set_config('request.jwt.claim.sub',:'owner',true);
select pg_temp.coin_error($q$select public.oi_save_farmer_outfit('{"version":1,"character":"kyu","slots":{"top":"kyu-3916-2673"}}')$q$,'PT403');
select pg_temp.check_coin(public.oi_purchase_farmer_item('kyu:top:kyu-3916-2673','f5060000-0000-4000-8000-000000000401') @> '{"purchased":true,"wallet":{"balance":8}}','first item costs3');
select pg_temp.check_coin(public.oi_purchase_farmer_item('kyu:top:kyu-3916-2673','f5060000-0000-4000-8000-000000000401') @> '{"purchased":false,"wallet":{"balance":8}}','purchase replay free');
select pg_temp.coin_error($q$select public.oi_purchase_farmer_item('kyu:top:kyu-3916-2718','f5060000-0000-4000-8000-000000000401')$q$,'PT409');
select public.oi_save_farmer_outfit('{"version":1,"character":"kyu","slots":{"top":"kyu-3916-2673"}}');
select pg_temp.coin_error($q$select public.oi_purchase_farmer_item('kyu:top:invented','f5060000-0000-4000-8000-000000000402')$q$,'22023');
select set_config('request.jwt.claim.sub',:'unlimited',true);
select pg_temp.check_coin(public.oi_pickle_wallet() @> '{"balance":10,"unlimited":true}','private server unlimited flag');
select pg_temp.check_coin(public.oi_purchase_farmer_item('kyu:top:kyu-3916-2673','f5060000-0000-4000-8000-000000000403') @> '{"purchased":true,"wallet":{"balance":10}}','unlimited purchase preserves finite balance');
select set_config('request.jwt.claim.sub',:'owner',true);
select public.oi_start_coin_evidence(:'certificate');
select pg_temp.coin_error(format('select public.oi_submit_coin_evidence(%L,%L,0)',:'certificate',:'owner'||'/'||:'certificate'||'/certificate.pdf'),'22023');
insert into storage.objects(bucket_id,name,metadata) values('oi-evidence',:'owner'||'/'||:'certificate'||'/certificate.pdf','{"mimetype":"application/pdf","size":100}');
select public.oi_submit_coin_evidence(:'certificate',:'owner'||'/'||:'certificate'||'/certificate.pdf',1) as submitted \gset
update storage.objects set metadata='{}' where name=:'owner'||'/'||:'certificate'||'/certificate.pdf';
select pg_temp.check_coin((select metadata->>'mimetype'='application/pdf' from storage.objects where name=:'owner'||'/'||:'certificate'||'/certificate.pdf'),'evidence replacement denied by RLS');
select pg_temp.coin_error(format('select public.oi_mutate(''start_evidence'',jsonb_build_object(''id'',%L))',gen_random_uuid()),'PT410');
set local role service_role;
select public.oi_prepare_coin_evidence(:'owner',:'session',:'certificate');
select pg_temp.coin_error(format('select public.oi_prepare_coin_evidence(%L,%L,%L)',:'owner',:'session',:'certificate'),'PT409');
select pg_temp.coin_error(format('select public.oi_coin_evidence_review(%L,%L,%L,%L,%L,%L,null,''approved'',null)',:'owner',:'session',:'certificate',:'submitted'::jsonb->>'object_path',:'submitted'::jsonb->>'submitted_at',repeat('d',64)),'22023');
select pg_temp.coin_error(format('select public.oi_coin_evidence_review(%L,%L,%L,%L,%L,%L,%L,''approved'',null)',:'owner',:'unlimited_session',:'certificate',:'submitted'::jsonb->>'object_path',:'submitted'::jsonb->>'submitted_at',repeat('d',64),repeat('c',64)),'PT401');
select public.oi_coin_evidence_review(:'owner',:'session',:'certificate',:'submitted'::jsonb->>'object_path',(:'submitted'::jsonb->>'submitted_at')::timestamptz,repeat('d',64),repeat('c',64),'approved','certificate_verified') as approved \gset
select pg_temp.check_coin(:'approved'::jsonb @> '{"credited":true,"duplicate":false,"wallet":{"balance":38}}','verified certificate pays30 without minimum amount');
select pg_temp.check_coin(public.oi_coin_evidence_review(:'owner',:'session',:'certificate',:'submitted'::jsonb->>'object_path',(:'submitted'::jsonb->>'submitted_at')::timestamptz,repeat('d',64),repeat('c',64),'approved',null) @> '{"credited":false,"wallet":{"balance":38}}','lost callback response retry does not mint');
set local role authenticated;
select pg_temp.check_coin(public.oi_cancel_coin_evidence(:'certificate') @> '{"request":{"status":"approved"},"wallet":{"balance":38},"credited":false}','cancel after callback preserves approved receipt and paid balance');
select pg_temp.check_coin(public.oi_cancel_coin_evidence('f5060000-0000-4000-8000-000000000318') @> '{"request":{"status":"rejected","review_note":"certificate_cancelled"},"credited":false}','missing start becomes authoritative cancelled operation');
select pg_temp.check_coin(public.oi_start_coin_evidence('f5060000-0000-4000-8000-000000000318')->>'review_note'='certificate_cancelled','late start cannot revive cancelled request');
reset role;
insert into public.oi_evidence_requests(id,user_id,storage_owner_id,status,object_path,submitted_at,coin_verification,coin_consent_version)
values('f5060000-0000-4000-8000-000000000319',:'owner',:'owner','pending',:'owner'||'/f5060000-0000-4000-8000-000000000319/corrupt.pdf','2026-11-18',true,1);
insert into storage.objects(bucket_id,name,metadata) values('oi-evidence',:'owner'||'/f5060000-0000-4000-8000-000000000319/corrupt.pdf','{"mimetype":"application/pdf","size":100}');
set local role authenticated;
select pg_temp.check_coin(public.oi_cancel_coin_evidence('f5060000-0000-4000-8000-000000000319') @> '{"request":{"status":"rejected","review_note":"certificate_cancelled"},"wallet":{"balance":38}}','pending corrupt upload can be cancelled without changing balance');
select pg_temp.check_coin((select count(*)=1 from storage.objects where name=:'owner'||'/f5060000-0000-4000-8000-000000000319/corrupt.pdf'),'cancel preserves private original under retention policy');
select set_config('request.jwt.claim.sub',:'unlimited',true);
select pg_temp.coin_error($q$select public.oi_cancel_coin_evidence('f5060000-0000-4000-8000-000000000319')$q$,'42501');
set local role service_role;
select pg_temp.coin_error(format('select public.oi_coin_evidence_review(%L,%L,%L,%L,%L,%L,%L,''approved'',null)',:'owner',:'session','f5060000-0000-4000-8000-000000000319',:'owner'||'/f5060000-0000-4000-8000-000000000319/corrupt.pdf','2026-11-18',repeat('9',64),repeat('8',64)),'PT409');
reset role;
select pg_temp.check_coin(not exists(select 1 from public.oi_writing_grants where user_id=:'owner'),'certificate never creates a writing grant');
insert into public.oi_evidence_requests(id,user_id,storage_owner_id,status,object_path,submitted_at,coin_verification,coin_consent_version)
values('f5060000-0000-4000-8000-000000000302',:'unlimited',:'unlimited','pending',:'unlimited'||'/f5060000-0000-4000-8000-000000000302/copy.pdf','2026-11-18',true,1);
set local role service_role;
select pg_temp.check_coin(public.oi_coin_evidence_review(:'unlimited',:'unlimited_session','f5060000-0000-4000-8000-000000000302',:'unlimited'||'/f5060000-0000-4000-8000-000000000302/copy.pdf','2026-11-18',repeat('e',64),repeat('c',64),'approved',null) @> '{"credited":false,"duplicate":true,"request":{"status":"rejected","review_note":"duplicate_certificate"}}','same certificate photographed again cannot pay another account');
reset role;
-- Keep composite facts and optional certificate references separate. Two valid
-- different references with equal donor/date/amount are distinct certificates.
insert into public.oi_evidence_requests(id,user_id,storage_owner_id,status,object_path,submitted_at,coin_verification,coin_consent_version)
select ('f5060000-0000-4000-8000-000000000'||n)::uuid, :'unlimited', :'unlimited','pending',
 :'unlimited'||'/f5060000-0000-4000-8000-000000000'||n||'/certificate.pdf','2026-11-18',true,1
from generate_series(303,307)n;
set local role service_role;
select pg_temp.check_coin(public.oi_coin_evidence_review(:'unlimited',:'unlimited_session','f5060000-0000-4000-8000-000000000303',:'unlimited'||'/f5060000-0000-4000-8000-000000000303/certificate.pdf','2026-11-18',repeat('3',64),repeat('f',64),'approved',null,repeat('1',64))->'credited'='true'::jsonb,'first referenced certificate earns30');
select pg_temp.check_coin(public.oi_coin_evidence_review(:'unlimited',:'unlimited_session','f5060000-0000-4000-8000-000000000304',:'unlimited'||'/f5060000-0000-4000-8000-000000000304/certificate.pdf','2026-11-18',repeat('4',64),repeat('f',64),'approved',null,repeat('2',64))->'credited'='true'::jsonb,'distinct references with same composite each earn30');
select pg_temp.check_coin(public.oi_coin_evidence_review(:'unlimited',:'unlimited_session','f5060000-0000-4000-8000-000000000305',:'unlimited'||'/f5060000-0000-4000-8000-000000000305/certificate.pdf','2026-11-18',repeat('5',64),repeat('f',64),'approved',null)->'duplicate'='true'::jsonb,'hiding a paid certificate reference cannot earn another reward');
select pg_temp.check_coin(public.oi_coin_evidence_review(:'unlimited',:'unlimited_session','f5060000-0000-4000-8000-000000000306',:'unlimited'||'/f5060000-0000-4000-8000-000000000306/certificate.pdf','2026-11-18',repeat('6',64),repeat('e',64),'approved',null)->'credited'='true'::jsonb,'first readable unnumbered certificate earns30');
select pg_temp.check_coin(public.oi_coin_evidence_review(:'unlimited',:'unlimited_session','f5060000-0000-4000-8000-000000000307',:'unlimited'||'/f5060000-0000-4000-8000-000000000307/certificate.pdf','2026-11-18',repeat('7',64),repeat('e',64),'approved',null,repeat('8',64))->'duplicate'='true'::jsonb,'showing a previously hidden reference cannot repay same composite');
reset role;
-- Five analysis starts per canonical account per minute, across isolates.
insert into public.oi_evidence_requests(id,user_id,storage_owner_id,status,object_path,submitted_at,coin_verification,coin_consent_version)
select ('f5060000-0000-4000-8000-000000000'||n)::uuid, :'unlimited', :'unlimited','pending',
 :'unlimited'||'/f5060000-0000-4000-8000-000000000'||n||'/certificate.pdf','2026-11-18',true,1
from generate_series(311,316)n;
set local role service_role;
select public.oi_prepare_coin_evidence(:'unlimited',:'unlimited_session',('f5060000-0000-4000-8000-000000000'||n)::uuid) from generate_series(311,315)n;
select pg_temp.coin_error(format('select public.oi_prepare_coin_evidence(%L,%L,%L)',:'unlimited',:'unlimited_session','f5060000-0000-4000-8000-000000000316'),'PT429');
reset role;
-- A complete synthetic review uses the same snapshot/plant RPCs as the app.
create function pg_temp.coin_submission(p_id uuid,p_revision integer) returns jsonb language sql as $$
 select jsonb_build_object('id',p_id,'revision',p_revision,'ai_review_consent_version',1,
   'card_snapshot_id','f5060000-0000-4000-8000-000000000501');
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub',:'owner',true);
select public.oi_mutate('save_story',pg_temp.coin_submission(:'story',0)||'{"region_id":"pond","title":"Synthetic story","body":"A campus memory","theme":"감사","emotion":"기쁨","cucumber_name":"Synthetic","cucumber_asset":"OiCats","card_asset":"MYBasicCard","latitude":36.01261057,"longitude":129.31972687}');
reset role;
insert into storage.objects(bucket_id,name,metadata) values
 ('oi-story-media',:'owner'||'/'||:'story'||'/photo.jpg','{"mimetype":"image/jpeg","size":100}'),
 ('oi-story-media',:'owner'||'/'||:'story'||'/card/f5060000-0000-4000-8000-000000000501.png','{"mimetype":"image/png","size":100}');
insert into public.oi_story_media(story_id,object_path,position) values(:'story',:'owner'||'/'||:'story'||'/photo.jpg',0);
set local role service_role;
select public.oi_moderate_story(:'owner',:'session',pg_temp.coin_submission(:'story',1)) as review \gset
select public.oi_moderate_story(:'owner',:'session',pg_temp.coin_submission(:'story',1),:'review'::jsonb->>'snapshot') as verdict \gset
set local role authenticated;
select public.oi_plant_story(:'story',(:'verdict'::jsonb->>'revision')::integer) as planted \gset
select pg_temp.check_coin(:'planted'::jsonb @> '{"status":"published","coin_cost":30,"wallet":{"balance":8}}','first public planting costs30 atomically');
select public.oi_mutate('reopen_story',jsonb_build_object('id',:'story','revision',(:'planted'::jsonb->>'revision')::integer)) as reopened \gset
set local role service_role;
select public.oi_moderate_story(:'owner',:'session',pg_temp.coin_submission(:'story',(:'reopened'::jsonb->>'revision')::integer)) as review \gset
select public.oi_moderate_story(:'owner',:'session',pg_temp.coin_submission(:'story',(:'reopened'::jsonb->>'revision')::integer),:'review'::jsonb->>'snapshot') as verdict \gset
set local role authenticated;
select pg_temp.check_coin(public.oi_plant_story(:'story',(:'verdict'::jsonb->>'revision')::integer) @> '{"coin_cost":0,"wallet":{"balance":8}}','editing and replanting same story free');
reset role;
-- An insufficient balance rolls publication, its receipt and side effects back.
insert into public.oi_stories(id,user_id,storage_owner_id,region_id,title,body,theme,emotion,cucumber_name,cucumber_asset,card_asset,latitude,longitude,status)
values('f5060000-0000-4000-8000-000000000104',:'owner',:'owner','pond','Second synthetic story','Second memory','theme','emotion','Second','OiCats','MYBasicCard',36.01261057,129.31972687,'draft');
insert into storage.objects(bucket_id,name,metadata) values
 ('oi-story-media',:'owner'||'/f5060000-0000-4000-8000-000000000104/photo.jpg','{"mimetype":"image/jpeg","size":100}'),
 ('oi-story-media',:'owner'||'/f5060000-0000-4000-8000-000000000104/card/f5060000-0000-4000-8000-000000000501.png','{"mimetype":"image/png","size":100}');
insert into public.oi_story_media(story_id,object_path,position) values('f5060000-0000-4000-8000-000000000104',:'owner'||'/f5060000-0000-4000-8000-000000000104/photo.jpg',0);
set local role service_role;
select public.oi_moderate_story(:'owner',:'session',pg_temp.coin_submission('f5060000-0000-4000-8000-000000000104',1)) as review \gset
select public.oi_moderate_story(:'owner',:'session',pg_temp.coin_submission('f5060000-0000-4000-8000-000000000104',1),:'review'::jsonb->>'snapshot') as verdict \gset
set local role authenticated;
select pg_temp.coin_error(format('select public.oi_plant_story(%L,%s)','f5060000-0000-4000-8000-000000000104',:'verdict'::jsonb->>'revision'),'PT402');
reset role;
select pg_temp.check_coin((select status='draft' from public.oi_stories where id='f5060000-0000-4000-8000-000000000104'),'insufficient coin story remains private draft');
select pg_temp.check_coin(not exists(select 1 from benchmark_private.oi_pickle_plant_receipts where story_id='f5060000-0000-4000-8000-000000000104'),'insufficient coin receipt rolls back');
select pg_temp.check_coin((select balance=8 from benchmark_private.oi_pickle_wallets where account_id=:'owner'),'failed planting does not change wallet');
select pg_temp.coin_error($q$select benchmark_private.oi_mutate_internal('review_story','{"status":"published"}',null)$q$,'PT426');
-- A proof-only newly created login method contributes no additional signup grant.
set local role service_role;
select public.oi_merge_accounts('preview','f5060000-0000-4000-8000-000000000601',:'owner',:'proof',:'session',:'proof_session') as preview \gset
select public.oi_merge_accounts('confirm','f5060000-0000-4000-8000-000000000601',:'owner',:'proof',:'session',:'proof_session',(:'preview'::jsonb->>'challenge_id')::uuid,true);
reset role;
select pg_temp.check_coin((select balance=8 from benchmark_private.oi_pickle_wallets where account_id=:'owner'),'proof login merge grants no coins');
select pg_temp.check_coin(not exists(select 1 from benchmark_private.oi_pickle_wallets where account_id=:'proof'),'no proof wallet created');
set local role authenticated;
select set_config('request.jwt.claim.sub',:'source',true);
select public.oi_pickle_wallet();
select public.oi_mutate('collect',jsonb_build_object('id',:'old_story'));
set local role service_role;
select public.oi_merge_accounts('preview','f5060000-0000-4000-8000-000000000602',:'owner',:'source',:'session',:'source_session') as preview \gset
select public.oi_merge_accounts('confirm','f5060000-0000-4000-8000-000000000602',:'owner',:'source',:'session',:'source_session',(:'preview'::jsonb->>'challenge_id')::uuid,true);
reset role;
select pg_temp.check_coin((select balance=19 from benchmark_private.oi_pickle_wallets where account_id=:'owner'),'used account balances preserved on merge');
select pg_temp.check_coin((select count(*)=1 from benchmark_private.oi_pickle_collection_rewards where account_id=:'owner' and story_id=:'old_story'),'collection rewards union on merge');
select pg_temp.check_coin(not exists(select 1 from benchmark_private.oi_pickle_ledger where account_id=:'source'),'source ledger transferred to canonical account');
select pg_temp.check_coin(not exists(select 1 from pg_proc p where p.pronamespace='benchmark_private'::regnamespace
 and (p.proname like 'oi_pickle_%' or p.proname in ('oi_mutate_pickle_base','oi_merge_pickle_accounts'))
 and (has_function_privilege('authenticated',p.oid,'execute') or has_function_privilege('anon',p.oid,'execute'))),'coin helpers inaccessible to clients');
-- Existing account deletion removes wallets/ownership/claims with its private evidence.
set local role service_role;
select public.oi_delete_account('prepare',:'owner',:'session',:'owner',:'session',:'owner');
reset role;
delete from storage.objects where name like :'owner'||'/%';
set local role service_role;
select public.oi_delete_account('finish',:'owner',:'session',:'owner',:'session',:'owner');
reset role;
select pg_temp.check_coin(not exists(select 1 from benchmark_private.oi_pickle_wallets where account_id=:'owner'),'deletion removes wallet');
select pg_temp.check_coin(not exists(select 1 from benchmark_private.oi_pickle_ledger where account_id=:'owner'),'deletion removes ledger');
select pg_temp.check_coin(not exists(select 1 from benchmark_private.oi_coin_certificate_claims where evidence_id=:'certificate'),'deletion removes private certificate claim');
rollback;
