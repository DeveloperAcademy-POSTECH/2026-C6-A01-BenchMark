begin;

-- Count only requested published stories. The legacy paginated RPC aggregates the
-- entire catalog before PostgREST can apply its outer LIMIT/OFFSET.
create function benchmark_private.oi_collection_metrics_for_stories(p_story_ids uuid[])
returns table(story_id uuid, collection_count bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if cardinality(p_story_ids) > 200 then
    raise exception 'too_many_story_ids' using errcode = '22023';
  end if;

  return query
  select story.id, (
    select count(*) from public.oi_collections as collection
    where collection.story_id = story.id
  )
  from (select distinct id from unnest(p_story_ids) as requested(id)) as requested
  join public.oi_stories as story on story.id = requested.id
  where story.status = 'published';
end;
$$;
revoke all on function benchmark_private.oi_collection_metrics_for_stories(uuid[]) from public, anon, authenticated;
grant execute on function benchmark_private.oi_collection_metrics_for_stories(uuid[]) to anon, authenticated;

create function public.oi_collection_metrics_for_stories(p_story_ids uuid[])
returns table(story_id uuid, collection_count bigint)
language sql stable security invoker set search_path = '' as $$
  select * from benchmark_private.oi_collection_metrics_for_stories(p_story_ids);
$$;
revoke all on function public.oi_collection_metrics_for_stories(uuid[]) from public, anon, authenticated;
grant execute on function public.oi_collection_metrics_for_stories(uuid[]) to anon, authenticated;

notify pgrst, 'reload schema';
commit;
