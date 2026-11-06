-- All rows and paths are synthetic. Real storage bytes are removed only by the Edge Function.
begin;
insert into auth.users(id) values
 ('d1690000-0000-4000-8000-000000000001'), ('d1690000-0000-4000-8000-000000000002'),
 ('d1690000-0000-4000-8000-000000000003');
insert into auth.sessions(id,user_id) values
 ('d1690000-0000-4000-8000-000000000011','d1690000-0000-4000-8000-000000000001'),
 ('d1690000-0000-4000-8000-000000000012','d1690000-0000-4000-8000-000000000002'),
 ('d1690000-0000-4000-8000-000000000013','d1690000-0000-4000-8000-000000000003');
insert into auth.identities(user_id,provider) values ('d1690000-0000-4000-8000-000000000002','apple');
update benchmark_private.oi_account_members set account_id='d1690000-0000-4000-8000-000000000001'
where auth_user_id='d1690000-0000-4000-8000-000000000002';
insert into public.oi_evidence_requests(id,user_id,storage_owner_id,status,object_path) values
 ('d1690000-0000-4000-8000-000000000021','d1690000-0000-4000-8000-000000000001','d1690000-0000-4000-8000-000000000002','pending',
  'd1690000-0000-4000-8000-000000000002/d1690000-0000-4000-8000-000000000021/proof.png');
insert into public.oi_stories(id,user_id,storage_owner_id,region_id,title,body,theme,emotion,cucumber_name,cucumber_asset,card_asset,latitude,longitude,status) values
 ('d1690000-0000-4000-8000-000000000031','d1690000-0000-4000-8000-000000000001','d1690000-0000-4000-8000-000000000002','pond','Synthetic','Body','theme','emotion','one','OiCats','MYBasicCard',36,129,'published'),
 ('d1690000-0000-4000-8000-000000000033','d1690000-0000-4000-8000-000000000003','d1690000-0000-4000-8000-000000000003','pond','Unrelated','Body','theme','emotion','other','OiCats','MYBasicCard',36,129,'published');
insert into public.oi_collections(user_id,story_id) values
 ('d1690000-0000-4000-8000-000000000003','d1690000-0000-4000-8000-000000000031');
-- Retention policy: reports, restrictions, fingerprints and related audit rows
-- follow deletion of their owning account/story/evidence, including linked logins.
insert into benchmark_private.oi_content_reports(story_id,reporter_member_id,reason,detail) values
 ('d1690000-0000-4000-8000-000000000031','d1690000-0000-4000-8000-000000000003','other','Synthetic report about deleted story'),
 ('d1690000-0000-4000-8000-000000000033','d1690000-0000-4000-8000-000000000002','other','Synthetic report by deleted member');
insert into benchmark_private.oi_content_restrictions(member_id,note) values
 ('d1690000-0000-4000-8000-000000000002','Synthetic restriction');
insert into benchmark_private.oi_evidence_fingerprints(evidence_id,submitted_at,sha256) values
 ('d1690000-0000-4000-8000-000000000021',now(),repeat('0',64));
insert into benchmark_private.oi_audit(actor_id,action,target_id) values
 ('d1690000-0000-4000-8000-000000000003','content:hidden','d1690000-0000-4000-8000-000000000031'),
 ('d1690000-0000-4000-8000-000000000003','content:dismissed','d1690000-0000-4000-8000-000000000033');
insert into storage.objects(bucket_id,name,owner_id) values
 ('oi-evidence','d1690000-0000-4000-8000-000000000002/d1690000-0000-4000-8000-000000000021/proof.png','d1690000-0000-4000-8000-000000000002'),
 ('oi-evidence','d1690000-0000-4000-8000-000000000003/other/photo.png','d1690000-0000-4000-8000-000000000003');

do $$
begin
  if has_function_privilege('authenticated','public.oi_delete_account(text,uuid,uuid,uuid,uuid,uuid)','execute')
    or has_function_privilege('anon','public.oi_delete_account(text,uuid,uuid,uuid,uuid,uuid)','execute')
    then raise exception 'deletion must remain service-only'; end if;
  begin
    perform public.oi_delete_account('prepare','d1690000-0000-4000-8000-000000000001','d1690000-0000-4000-8000-000000000011',
      'd1690000-0000-4000-8000-000000000003','d1690000-0000-4000-8000-000000000013','d1690000-0000-4000-8000-000000000001');
    raise exception 'foreign login proof was accepted';
  exception when insufficient_privilege then null; end;
end;
$$;

create function pg_temp.delete_fixture(action text) returns jsonb language sql as $$
 select public.oi_delete_account(action,'d1690000-0000-4000-8000-000000000001','d1690000-0000-4000-8000-000000000011',
 'd1690000-0000-4000-8000-000000000002','d1690000-0000-4000-8000-000000000012','d1690000-0000-4000-8000-000000000001');
$$;
do $$
begin
 if jsonb_array_length(pg_temp.delete_fixture('prepare')->'files')<>1 then raise exception 'inventory is not account scoped'; end if;
 begin
   perform pg_temp.delete_fixture('finish');
   raise exception 'remaining Storage objects did not block deletion';
 exception when sqlstate 'PT409' then null; end;
end;
$$;

set local role anon;
do $$ begin
 if exists(select 1 from public.oi_stories where id='d1690000-0000-4000-8000-000000000031')
   then raise exception 'pending deletion remained public'; end if;
end; $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','d1690000-0000-4000-8000-000000000002',true);
do $$ begin
 if public.oi_account_deletion_status()->>'account_id' is distinct from 'd1690000-0000-4000-8000-000000000001'
    or benchmark_private.oi_deletion_upload_allowed() then raise exception 'linked member did not resume safely'; end if;
end; $$;
reset role;

-- Mimic successful Storage API cleanup in the local fake storage schema.
delete from storage.objects where owner_id='d1690000-0000-4000-8000-000000000002';
do $$
declare receipt jsonb;
begin
 receipt:=pg_temp.delete_fixture('finish');
 if receipt->>'deleted' is distinct from 'true' or receipt->>'apple_revocation_required' is distinct from 'true'
    or jsonb_array_length(receipt->'deleted_member_ids')<>2 then raise exception 'invalid deletion receipt'; end if;
 if exists(select 1 from auth.users where id in ('d1690000-0000-4000-8000-000000000001','d1690000-0000-4000-8000-000000000002'))
    or exists(select 1 from public.oi_stories where id='d1690000-0000-4000-8000-000000000031')
    or exists(select 1 from public.oi_evidence_requests where id='d1690000-0000-4000-8000-000000000021')
    or not exists(select 1 from public.oi_stories where id='d1690000-0000-4000-8000-000000000033')
    or not exists(select 1 from storage.objects where owner_id='d1690000-0000-4000-8000-000000000003')
    then raise exception 'data was retained or unrelated data was deleted'; end if;
 if exists(select 1 from benchmark_private.oi_content_reports where story_id='d1690000-0000-4000-8000-000000000031'
      or reporter_member_id='d1690000-0000-4000-8000-000000000002')
    or exists(select 1 from benchmark_private.oi_content_restrictions where member_id='d1690000-0000-4000-8000-000000000002')
    or exists(select 1 from benchmark_private.oi_evidence_fingerprints where evidence_id='d1690000-0000-4000-8000-000000000021')
    or exists(select 1 from benchmark_private.oi_audit where target_id='d1690000-0000-4000-8000-000000000031')
    or not exists(select 1 from benchmark_private.oi_audit where target_id='d1690000-0000-4000-8000-000000000033')
    then raise exception 'retention cleanup failed or unrelated audit was deleted'; end if;
end;
$$;
rollback;
