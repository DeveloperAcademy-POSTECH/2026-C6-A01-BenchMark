begin;
create function pg_temp.assert_true(value boolean,label text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception 'Assertion failed: %',label; end if; end; $$;
insert into auth.users values('70000000-0000-4000-8000-000000000001');
insert into public.oi_evidence_requests(id,user_id,storage_owner_id,status) values
 ('70000000-0000-4000-8000-000000000002','70000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000001','approved');
insert into public.oi_writing_grants(id,evidence_id,user_id,story_limit) values
 ('70000000-0000-4000-8000-000000000003','70000000-0000-4000-8000-000000000002','70000000-0000-4000-8000-000000000001',5);
set local role authenticated;
select set_config('request.jwt.claim.sub','70000000-0000-4000-8000-000000000001',true);
select public.oi_mutate('save_campus_story','{"id":"70000000-0000-4000-8000-000000000004","grant_id":"70000000-0000-4000-8000-000000000003","revision":0,"region_id":"pond","title":"Synthetic campus title","body":"Synthetic body","theme":"감사","emotion":"기쁨","cucumber_name":"Synthetic cucumber","cucumber_asset":"OiCats","card_asset":"MYBasicCard","latitude":36.01261057021347,"longitude":129.3197268697784,"height_meters":2.3,"heading_degrees":23.5}');
select pg_temp.assert_true((select status='pending' and revision=2 and height_meters=2.3 and heading_degrees=23.5 from public.oi_stories),'deployed campus action and geometry payload preserved');
select public.oi_mutate('save_campus_story','{"id":"70000000-0000-4000-8000-000000000004","grant_id":"70000000-0000-4000-8000-000000000003","revision":2,"region_id":"pond","title":"Updated campus title","body":"Synthetic body","theme":"감사","emotion":"기쁨","cucumber_name":"Synthetic cucumber","cucumber_asset":"OiCats","card_asset":"MYBasicCard","latitude":36.01261057021347,"longitude":129.3197268697784}');
select pg_temp.assert_true((select status='pending' and revision=5 and height_meters=2.3 and heading_degrees=23.5 from public.oi_stories),'omitted geometry retains existing values through reopen/save/submit');
rollback;
