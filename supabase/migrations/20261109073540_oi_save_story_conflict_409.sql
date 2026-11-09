begin;
set local lock_timeout = '2s';
set local statement_timeout = '10s';

-- The production hotfix may already be present when this migration runs.
do $patch$
declare
  definition text := pg_get_functiondef('benchmark_private.oi_mutate(text,jsonb)'::regprocedure);
  old_clause constant text := $clause$raise exception 'Story changed; refresh before editing' using errcode='40001';$clause$;
  new_clause constant text := $clause$raise exception 'Story changed; refresh before editing' using errcode='PT409';$clause$;
  old_count integer := (length(definition) - length(replace(definition, old_clause, ''))) / length(old_clause);
  new_count integer := (length(definition) - length(replace(definition, new_clause, ''))) / length(new_clause);
begin
  if old_count = 0 and new_count = 1 then
    return;
  end if;
  if old_count <> 1 or new_count <> 0 then
    raise exception 'Unexpected save_story conflict clause; review oi_mutate before applying';
  end if;
  execute replace(definition, old_clause, new_clause);
end;
$patch$;

commit;
