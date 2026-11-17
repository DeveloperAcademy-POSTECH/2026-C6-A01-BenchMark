begin;

-- Match the already deployed #418 functions before any definition is replaced.
do $drift$
declare patch record;
begin
 for patch in select * from (values
  ('benchmark_private.oi_check_continuation(uuid,uuid,uuid)','e62cfd913fb69286e7d5d7b8dc35e50f'),
  ('benchmark_private.oi_mutate_internal(text,jsonb,text)','ffac8db414a94f3f567895082c3698a4'),
  ('benchmark_private.oi_visible_continuations(uuid[])','7c680a27e516e3fe5ecb60db101caec2'),
  ('public.oi_story_continuation_counts(uuid[],uuid[])','8717f006b31aef8f438e785367ee7925'),
  ('public.oi_my_story_continuation_targets()','c9ec2334dcf4c41c8bd0a57e69b03ad2')
 ) expected(signature,source_md5) loop
  if (select md5(btrim(prosrc,E' \n\r\t')) from pg_proc where oid=patch.signature::regprocedure)
    is distinct from patch.source_md5 then
   raise exception 'Continuation deletion visibility drift: %',patch.signature;
  end if;
 end loop;
end; $drift$;

do $patch$
declare patch record; definition text;
begin
 for patch in select * from (values
  ('benchmark_private.oi_check_continuation(uuid,uuid,uuid)','and s.user_id<>p_owner and not benchmark_private.oi_content_restricted(s.user_id) for share;','and s.user_id<>p_owner and not benchmark_private.oi_content_restricted(s.user_id)
    and not benchmark_private.oi_account_is_deleting(s.user_id) for share;'),
  ('benchmark_private.oi_mutate_internal(text,jsonb,text)','and s.user_id<>owner_id and not benchmark_private.oi_content_restricted(s.user_id)','and s.user_id<>owner_id and not benchmark_private.oi_content_restricted(s.user_id)
        and not benchmark_private.oi_account_is_deleting(s.user_id)'),
  ('benchmark_private.oi_visible_continuations(uuid[])','and not benchmark_private.oi_content_restricted(parent.user_id)','and not benchmark_private.oi_content_restricted(parent.user_id)
    and not benchmark_private.oi_account_is_deleting(child.user_id)
    and not benchmark_private.oi_account_is_deleting(parent.user_id)'),
  ('public.oi_story_continuation_counts(uuid[],uuid[])','and not benchmark_private.oi_content_restricted(p.user_id)','and not benchmark_private.oi_content_restricted(p.user_id)
        and not benchmark_private.oi_account_is_deleting(p.user_id)'),
  ('public.oi_my_story_continuation_targets()','and not benchmark_private.oi_content_restricted(p.user_id)','and not benchmark_private.oi_content_restricted(p.user_id) and not benchmark_private.oi_account_is_deleting(p.user_id)'),
  ('public.oi_my_story_continuation_targets()','and child.status<>''deleted'';','and child.status<>''deleted'' and not benchmark_private.oi_account_is_deleting(child.user_id);')
 ) replacements(signature,anchor,replacement) loop
  definition:=pg_get_functiondef(patch.signature::regprocedure);
  if length(definition)-length(replace(definition,patch.anchor,''))<>length(patch.anchor) then
   raise exception 'Continuation deletion visibility anchor drift: %',patch.signature;
  end if;
  execute replace(definition,patch.anchor,patch.replacement);
 end loop;
end; $patch$;

notify pgrst,'reload schema';
commit;
