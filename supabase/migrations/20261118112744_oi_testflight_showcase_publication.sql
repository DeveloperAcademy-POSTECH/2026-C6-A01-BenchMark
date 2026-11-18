begin;

-- Temporary November 20 showcase exception. Disabled until the TF rollout is verified.
alter table benchmark_private.oi_story_creation_settings
  add column testflight_showcase_enabled boolean not null default false;

do $patch$
declare
  definition text := pg_get_functiondef('benchmark_private.oi_mutate_continuation_base(text,jsonb,text)'::regprocedure);
  anchor text := $old$moderation_step in ('prepare','approve')$old$;
begin
  if length(definition)-length(replace(definition,anchor,''))<>length(anchor) then
    raise exception 'Pending story publication requires migration review';
  end if;
  execute replace(definition,anchor,$new$moderation_step in ('prepare','approve','publish')$new$);
end; $patch$;

-- Only the Edge Function may call this after verifying Apple's signed Sandbox AppTransaction.
create function public.oi_publish_showcase_story(p_user uuid, p_session uuid, p_submission jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid;
begin
  if current_setting('role',true) is distinct from 'service_role' then
    raise exception 'Service role required' using errcode='42501';
  end if;
  perform 1 from auth.sessions where id=p_session and user_id=p_user for share;
  if not found then raise exception 'Sign in again' using errcode='PT401'; end if;
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p_user,'session_id',p_session,'role','authenticated')::text,true);
  actor := benchmark_private.oi_actor();
  perform 1 from benchmark_private.oi_story_creation_settings where singleton and testflight_showcase_enabled for share;
  if not found then raise exception 'Showcase publication unavailable' using errcode='PT503'; end if;
  if benchmark_private.oi_content_restricted(actor) then
    raise exception 'Content publication restricted' using errcode='42501';
  end if;
  -- Locks the current revision and validates ownership, writing availability, consent,
  -- photos, location, rendered appearance/card files and continuation references.
  perform benchmark_private.oi_story_review_snapshot(p_submission);
  -- Never synthesize an AI verdict. Normal publication checks and audit still run.
  return benchmark_private.oi_mutate_internal('submit_story',p_submission,'publish');
exception when serialization_failure then
  raise exception 'Story changed before publication' using errcode='PT409';
end;
$$;
revoke all on function public.oi_publish_showcase_story(uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.oi_publish_showcase_story(uuid,uuid,jsonb) to service_role;

notify pgrst,'reload schema';
commit;
