begin;

-- Explicit operator review coexists with AI review. Preserve the audited
-- authorization, row lock, revision, artwork and continuation checks.
do $patch$
declare
  mutation text := pg_get_functiondef('benchmark_private.oi_mutate_continuation_base(text,jsonb,text)'::regprocedure);
  capability text := pg_get_functiondef('public.oi_capabilities()'::regprocedure);
  blocked constant text := $old$    if action='review_story' and payload->>'status'='published'
      and benchmark_private.oi_auto_moderation_enabled() then
      raise exception 'Publication requires automatic review' using errcode='42501';
    end if;
$old$;
  anchor constant text := '''story_continuation_notifications'',true';
begin
  -- Canonical/deployed histories, with and without #426 pending preservation.
  if (select md5(btrim(prosrc,E' \n\r\t')) from pg_proc
      where oid='benchmark_private.oi_mutate_continuation_base(text,jsonb,text)'::regprocedure)
      not in ('dd7aeb06bbe54ec3e32f81bbdb2069c4','fb98036b9acccd39966c098f2d01dfc8',
              'af6728251826d1550d1c5d2a6aab4584','afeadc02cbdd90f1222919866120e7b9')
    or (select md5(btrim(prosrc,E' \n\r\t')) from pg_proc
      where oid='public.oi_capabilities()'::regprocedure)<>'dfd2bbd2c1864b9146432ff3f533f6bb'
    or length(mutation)-length(replace(mutation,blocked,''))<>length(blocked)
    or length(capability)-length(replace(capability,anchor,''))<>length(anchor) then
    raise exception 'Operator manual review drift requires audited migration';
  end if;
  execute replace(mutation,blocked,'');
  execute replace(capability,anchor,anchor||',''operator_manual_story_review'',true');
end;
$patch$;

notify pgrst,'reload schema';
commit;
