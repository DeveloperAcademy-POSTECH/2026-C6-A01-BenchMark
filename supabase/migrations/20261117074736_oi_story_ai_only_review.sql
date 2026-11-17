begin;

-- All public campus mutations reach this wrapper. The service-only AI RPC
-- continues through the guarded internal mutator and stores its verdict.
create or replace function benchmark_private.oi_mutate(action text, payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  if action='submit_story' then
    raise exception 'Update the app to publish this story' using errcode='PT426';
  end if;
  if action='review_story' and payload->>'status'='published' then
    raise exception 'Publication requires automatic review' using errcode='42501';
  end if;
  return benchmark_private.oi_mutate_internal(action,payload,null);
end;
$$;

do $patch$
declare
  definition text := pg_get_functiondef('public.oi_capabilities()'::regprocedure);
  anchor constant text := '''operator_manual_story_review'',true';
begin
  if length(definition)-length(replace(definition,anchor,''))<>length(anchor) then
    raise exception 'Operator review capability drift requires inspection';
  end if;
  execute replace(definition,anchor,'''operator_manual_story_review'',false');
end;
$patch$;

alter table benchmark_private.oi_story_creation_settings alter column auto_moderation_enabled set default true;
update benchmark_private.oi_story_creation_settings set auto_moderation_enabled=true where singleton;

notify pgrst,'reload schema';
commit;
