begin;

-- Education IDs are caller-generated UUIDs and may equal an ID in a different
-- channel. Account deletion must remove only this channel's target audit rows.
create or replace function benchmark_private.oi_education_cleanup_audit() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 delete from benchmark_private.oi_audit where target_id=old.id and action like 'education:%';
 return old;
end; $$;

commit;
