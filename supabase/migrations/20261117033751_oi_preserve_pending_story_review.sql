begin;

-- A legacy pending story participates in preparation without leaving the
-- operator queue. Approval and rejection change its status in the verdict transaction.
do $patch$
declare
  mutation text := pg_get_functiondef('benchmark_private.oi_mutate_internal(text,jsonb,text)'::regprocedure);
  moderation text := pg_get_functiondef('public.oi_moderate_story(uuid,uuid,jsonb,text,text,text)'::regprocedure);
  before_mutation text := $old$      if story.status<>'draft' then raise exception 'Only drafts can be submitted' using errcode='22023'; end if;$old$;
  after_mutation text := $new$      if story.status<>'draft' and not (
        story.status='pending' and coalesce(moderation_step in ('prepare','approve'),false)
      ) then raise exception 'Only drafts can be submitted' using errcode='22023'; end if;$new$;
  before_moderation text := $old$      'id',target_story,'revision',review_revision))->>'snapshot';
  end if;$old$;
  after_moderation text := $new$      'id',target_story,'revision',review_revision))->>'snapshot';
  elsif exists(select 1 from public.oi_stories where id=target_story and status='pending') then
    reviewed := benchmark_private.oi_mutate_internal('reopen_story',p_submission,null);
    review_revision := (reviewed->>'revision')::integer;
  end if;$new$;
begin
  if length(mutation)-length(replace(mutation,before_mutation,''))<>length(before_mutation)
    or length(moderation)-length(replace(moderation,before_moderation,''))<>length(before_moderation) then
    raise exception 'Story review drift requires pending-story migration check';
  end if;
  execute replace(mutation,before_mutation,after_mutation);
  execute replace(moderation,before_moderation,after_moderation);
end;
$patch$;

commit;
