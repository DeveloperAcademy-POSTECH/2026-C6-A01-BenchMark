-- Point-in-time deployed continuation wrapper, captured 2026-11-18.
-- No user data or credentials. Preserve this body for migration compatibility checks.
CREATE OR REPLACE FUNCTION benchmark_private.oi_mutate_internal(action text, payload jsonb, moderation_step text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb; target uuid; parent uuid; owner_id uuid;
begin
  -- Always obtain the topology lock before the existing story row lock.
  if action in ('save_story','submit_story','delete_story','review_story') then
    perform pg_advisory_xact_lock(418,1);
  end if;
  result := benchmark_private.oi_mutate_continuation_base(action,payload,moderation_step);
  if action in ('save_story','attach_media','reopen_story','submit_story','review_story') then
    target := (result->>'id')::uuid;
    owner_id := (result->>'user_id')::uuid;
    select parent_story_id into parent from benchmark_private.oi_story_continuations where child_story_id=target;
    if action='save_story' and payload ? 'continued_from_story_id' then
      parent := (payload->>'continued_from_story_id')::uuid;
      perform benchmark_private.oi_check_continuation(target,parent,owner_id);
      insert into benchmark_private.oi_story_continuations as old(child_story_id,parent_story_id)
        values(target,parent)
      on conflict(child_story_id) do update set parent_story_id=excluded.parent_story_id,
        published_at=case when old.parent_story_id is distinct from excluded.parent_story_id then null else old.published_at end,
        read_at=case when old.parent_story_id is distinct from excluded.parent_story_id then null else old.read_at end;
    elsif action='submit_story' or (action='review_story' and payload->>'status'='published') then
      perform benchmark_private.oi_check_continuation(target,parent,owner_id);
    end if;
    -- Only the authenticated owner/mutation caller gets draft metadata; raw public rows do not.
    result := result || jsonb_build_object('continued_from_story_id',
      (select s.id from public.oi_stories s where s.id=parent and s.status='published'
        and s.user_id<>owner_id and not benchmark_private.oi_content_restricted(s.user_id)
        and not benchmark_private.oi_account_is_deleting(s.user_id)));
  end if;
  return result;
end;
$function$;
