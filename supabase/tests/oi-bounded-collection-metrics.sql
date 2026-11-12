begin;

insert into auth.users(id) values
  ('28700000-0000-4000-8000-000000000001'),
  ('28700000-0000-4000-8000-000000000002');

insert into public.oi_stories(id, user_id, storage_owner_id, region_id, title, body, theme, emotion,
  cucumber_name, cucumber_asset, card_asset, latitude, longitude, status)
select id::uuid, '28700000-0000-4000-8000-000000000001', '28700000-0000-4000-8000-000000000001',
  'pond', 'Synthetic story', 'Synthetic body', 'Thanks', 'Joy', 'Cucumber', 'OiCats', 'MYBlueCard', 36.01261, 129.31972, status
from (values
  ('28700000-0000-4000-8000-000000000011', 'published'),
  ('28700000-0000-4000-8000-000000000012', 'published'),
  ('28700000-0000-4000-8000-000000000013', 'hidden'),
  ('28700000-0000-4000-8000-000000000014', 'draft')
) as fixture(id, status);

insert into public.oi_collections(user_id, story_id) values
  ('28700000-0000-4000-8000-000000000001', '28700000-0000-4000-8000-000000000011'),
  ('28700000-0000-4000-8000-000000000002', '28700000-0000-4000-8000-000000000011'),
  ('28700000-0000-4000-8000-000000000002', '28700000-0000-4000-8000-000000000013');

set local role anon;
do $$
declare
  requested uuid[] := array[
    '28700000-0000-4000-8000-000000000011', '28700000-0000-4000-8000-000000000011',
    '28700000-0000-4000-8000-000000000012', '28700000-0000-4000-8000-000000000013',
    '28700000-0000-4000-8000-000000000014', '28700000-0000-4000-8000-000000000099', null
  ]::uuid[];
  result bigint[];
begin
  select array_agg(collection_count order by story_id) into result
    from public.oi_collection_metrics_for_stories(requested);
  if result is distinct from array[2,0]::bigint[] then
    raise exception 'Expected two published stories including the one with zero collections, got %', result;
  end if;
  if exists (select * from public.oi_collection_metrics_for_stories('{}'::uuid[])) then
    raise exception 'Empty input must not query the public catalog';
  end if;
  if (select count(*) from public.oi_collection_metrics_for_stories(array_fill(requested[1], array[200]))) <> 1 then
    raise exception 'The maximum batch must deduplicate input';
  end if;
  begin
    perform public.oi_collection_metrics_for_stories(array_fill(requested[1], array[201]));
    raise exception 'An oversized batch must be rejected';
  exception when invalid_parameter_value then
    null;
  end;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','28700000-0000-4000-8000-000000000002',true);
do $$
begin
  if (select collection_count from public.oi_collection_metrics_for_stories(
      '{28700000-0000-4000-8000-000000000011}'::uuid[])) is distinct from 2::bigint then
    raise exception 'Authenticated callers must see the public count, including other collectors';
  end if;
  if exists(select * from public.oi_collection_metrics_for_stories(
      '{28700000-0000-4000-8000-000000000013}'::uuid[])) then
    raise exception 'A collection owner must not receive metrics for a hidden story';
  end if;
end;
$$;

rollback;
