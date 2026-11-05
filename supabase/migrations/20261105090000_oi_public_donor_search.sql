begin;

-- Optional, deliberately published search metadata. No backfill from auth or evidence.
-- Existing profile RLS exposes only the owner/operator and authors of published stories.
alter table public.oi_profiles
  add column public_name text not null default '' check (length(public_name) <= 50),
  add column department text not null default '' check (length(department) <= 100),
  add column admission_year text not null default ''
    check (admission_year = '' or admission_year ~ '^[0-9]{2}([0-9]{2})?$');
comment on column public.oi_profiles.public_name is 'Owner-entered public donor name; not nickname or evidence-derived name';
comment on column public.oi_profiles.department is 'Owner-entered public department for donor search';
comment on column public.oi_profiles.admission_year is 'Public admission cohort (26 or 2026), never a full student ID';
grant update(public_name, department, admission_year) on public.oi_profiles to authenticated;

notify pgrst, 'reload schema';
commit;
