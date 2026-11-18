-- Synthetic existing data proves rollout grants and grandfathering.
insert into auth.users(id) values
 ('f5060000-0000-4000-8000-000000000001'),('f5060000-0000-4000-8000-000000000002'),('f5060000-0000-4000-8000-000000000003');
insert into public.oi_stories(id,user_id,storage_owner_id,region_id,title,body,theme,emotion,cucumber_name,cucumber_asset,card_asset,latitude,longitude,status)
values
 ('f5060000-0000-4000-8000-000000000101','f5060000-0000-4000-8000-000000000001','f5060000-0000-4000-8000-000000000001','pond','Synthetic memory','Synthetic body','theme','emotion','Synthetic','OiCats','MYBasicCard',36.01261057,129.31972687,'published'),
 ('f5060000-0000-4000-8000-000000000102','f5060000-0000-4000-8000-000000000003','f5060000-0000-4000-8000-000000000003','pond','Other memory','Other body','theme','emotion','Other','OiCats','MYBasicCard',36.01261057,129.31972687,'published');
insert into public.oi_collections(user_id,story_id) values('f5060000-0000-4000-8000-000000000002','f5060000-0000-4000-8000-000000000101');
insert into benchmark_private.oi_farmer_outfits(account_id,outfit)
 values('f5060000-0000-4000-8000-000000000001','{"version":1,"character":"kyu","slots":{"top":"kyu-3916-2673"}}');
insert into public.oi_evidence_requests(id,user_id,storage_owner_id,status,object_path,submitted_at,reviewed_at)
values
 ('f5060000-0000-4000-8000-000000000201','f5060000-0000-4000-8000-000000000002','f5060000-0000-4000-8000-000000000002','approved','f5060000-0000-4000-8000-000000000002/f5060000-0000-4000-8000-000000000201/certificate.pdf','2026-11-01','2026-11-02'),
 ('f5060000-0000-4000-8000-000000000202','f5060000-0000-4000-8000-000000000003','f5060000-0000-4000-8000-000000000003','approved','f5060000-0000-4000-8000-000000000003/f5060000-0000-4000-8000-000000000202/copy.pdf','2026-11-01','2026-11-03');
insert into benchmark_private.oi_evidence_fingerprints(evidence_id,submitted_at,sha256,semantic_digest)
values ('f5060000-0000-4000-8000-000000000201','2026-11-01',repeat('a',64),repeat('b',64)),
 ('f5060000-0000-4000-8000-000000000202','2026-11-01',repeat('a',64),repeat('b',64));
