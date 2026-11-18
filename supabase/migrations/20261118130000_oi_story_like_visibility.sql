begin;

-- #513: SECURITY DEFINER like RPCs must honor the same deletion visibility as
-- public story RLS. Preserve their existing bodies, signatures and privileges.
do $patch$
declare
  definition text := pg_get_functiondef('benchmark_private.oi_story_likeable(uuid)'::regprocedure);
  anchor constant text := 'and not benchmark_private.oi_content_restricted(s.user_id));';
begin
  if length(definition)-length(replace(definition,anchor,''))<>length(anchor) then
    raise exception 'Story like visibility drift requires review';
  end if;
  execute replace(definition,anchor,
    'and not benchmark_private.oi_content_restricted(s.user_id)'||chr(10)||
    '    and not benchmark_private.oi_account_is_deleting(s.user_id));');
end;
$patch$;

notify pgrst,'reload schema';
commit;
