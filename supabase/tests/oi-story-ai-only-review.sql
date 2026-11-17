\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values('a4450000-0000-4000-8000-000000000001');
insert into benchmark_private.oi_operators values('a4450000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','a4450000-0000-4000-8000-000000000001',true);
do $$
begin
 if public.oi_capabilities() @> '{"auto_story_moderation":true,"operator_manual_story_review":false}' is not true then
  raise exception 'Only AI moderation should be available';
 end if;
 begin
  perform public.oi_mutate('submit_story','{}');
  raise exception 'Legacy submission accepted';
 exception when sqlstate 'PT426' then null;
 end;
 begin
  perform public.oi_mutate('review_story','{"status":"published"}');
  raise exception 'Manual publication accepted';
 exception when insufficient_privilege then null;
 end;
end; $$;
reset role;
update benchmark_private.oi_story_creation_settings set auto_moderation_enabled=false;
set local role authenticated;
do $$
begin
 begin
  perform public.oi_mutate('review_story','{"status":"published"}');
  raise exception 'Manual fallback opened after automatic moderation disabled';
 exception when insufficient_privilege then null;
 end;
end; $$;
rollback;
