begin;

-- Only the already-public POSTECH reference summaries and portraits belong here.
-- User-written stories, drafts, photos and card artwork remain in the existing
-- private education tables / oi-story-media bucket and require content review.
-- No client upload, listing, update or deletion policy is granted for this bucket.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('oi-education-reference','oi-education-reference',true,1048576,
 array['application/json','image/webp']);

commit;
