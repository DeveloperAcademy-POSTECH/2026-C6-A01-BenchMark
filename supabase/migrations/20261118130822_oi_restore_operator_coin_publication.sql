begin;

-- Restore the existing operator permission checks; coins must not add a publication gate.
do $patch$
declare
  definition text := pg_get_functiondef('benchmark_private.oi_mutate_internal(text,jsonb,text)'::regprocedure);
  anchor constant text := $old$  if action='review_story' and payload->>'status'='published' then
    raise exception 'The author must plant the reviewed story' using errcode='PT426';
  end if;
$old$;
begin
  if (select md5(btrim(prosrc,E' \n\r\t')) from pg_proc
      where oid='benchmark_private.oi_mutate_internal(text,jsonb,text)'::regprocedure)
      <> 'ba3e3e65cf89c0a32460e93d339f982a'
    or length(definition)-length(replace(definition,anchor,''))<>length(anchor) then
    raise exception 'Operator coin publication drift requires review';
  end if;
  execute replace(definition,anchor,'');
end; $patch$;

notify pgrst,'reload schema';
commit;
