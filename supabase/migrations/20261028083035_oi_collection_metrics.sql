begin;
create function benchmark_private.oi_collection_metrics()
returns table(story_id uuid,collection_count bigint)
language sql stable security definer set search_path = '' as $$
  select story.id,count(collection.story_id)
  from public.oi_stories story
  left join public.oi_collections collection on collection.story_id=story.id
  where story.status='published'
  group by story.id;
$$;
revoke all on function benchmark_private.oi_collection_metrics() from public;
grant execute on function benchmark_private.oi_collection_metrics() to anon,authenticated;
create function public.oi_collection_metrics()
returns table(story_id uuid,collection_count bigint)
language sql stable security invoker set search_path = '' as $$
  select * from benchmark_private.oi_collection_metrics();
$$;
revoke all on function public.oi_collection_metrics() from public;
grant execute on function public.oi_collection_metrics() to anon,authenticated;
commit;
