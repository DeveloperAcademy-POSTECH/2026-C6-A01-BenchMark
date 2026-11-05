begin;
create index oi_audit_created_id_idx on benchmark_private.oi_audit(created_at desc,id desc);

-- Read limits bound individual queries; they do not define a retention policy.
create function benchmark_private.oi_operator_audit(
  p_from timestamptz, p_until timestamptz, p_category text default 'all',
  p_cursor_at timestamptz default null, p_cursor_id bigint default null,
  p_limit integer default 50
) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  perform benchmark_private.oi_actor();
  if not benchmark_private.oi_is_operator() then
    raise exception 'Operator required' using errcode='42501';
  end if;
  if p_from is null or p_until is null or not isfinite(p_from) or not isfinite(p_until)
    or p_from>=p_until or p_until-p_from>interval '31 days'
    or p_limit is null or p_limit not between 1 and 50
    or p_category is null or p_category not in ('all','evidence','stories','accounts')
    or (p_cursor_at is null)<>(p_cursor_id is null)
    or (p_cursor_at is not null and (not isfinite(p_cursor_at) or p_cursor_at<p_from or p_cursor_at>=p_until or p_cursor_id<1)) then
    raise exception 'Invalid audit query' using errcode='22023';
  end if;
  return (
    with matches as materialized (
      select id,actor_id,action,target_id,created_at
      from benchmark_private.oi_audit
      where created_at>=p_from and created_at<p_until
        and (p_cursor_at is null or (created_at,id)<(p_cursor_at,p_cursor_id))
        and (p_category='all'
          or (p_category='evidence' and starts_with(action,'review_evidence:'))
          or (p_category='stories' and action in ('save_story','save_campus_story','attach_media','submit_story','reopen_story','delete_story','review_story'))
          or (p_category='accounts' and action='merge_accounts'))
      order by created_at desc,id desc limit p_limit+1
    ), page as (
      select * from matches order by created_at desc,id desc limit p_limit
    )
    select jsonb_build_object(
      'records',coalesce((select jsonb_agg(jsonb_build_object('id',id::text,'actor_id',actor_id,
        'action',action,'target_id',target_id,'created_at',created_at) order by created_at desc,id desc) from page),'[]'::jsonb),
      'next_cursor',case when (select count(*) from matches)>p_limit then
        (select jsonb_build_object('created_at',created_at,'id',id::text) from page order by created_at,id limit 1)
        else null end
    )
  );
end;
$$;
revoke all on function benchmark_private.oi_operator_audit(timestamptz,timestamptz,text,timestamptz,bigint,integer) from public,anon;
grant execute on function benchmark_private.oi_operator_audit(timestamptz,timestamptz,text,timestamptz,bigint,integer) to authenticated;

create function public.oi_operator_audit(
  p_from timestamptz, p_until timestamptz, p_category text default 'all',
  p_cursor_at timestamptz default null, p_cursor_id bigint default null,
  p_limit integer default 50
) returns jsonb language sql security invoker set search_path='' as $$
  select benchmark_private.oi_operator_audit(p_from,p_until,p_category,p_cursor_at,p_cursor_id,p_limit);
$$;
revoke all on function public.oi_operator_audit(timestamptz,timestamptz,text,timestamptz,bigint,integer) from public,anon;
grant execute on function public.oi_operator_audit(timestamptz,timestamptz,text,timestamptz,bigint,integer) to authenticated;
notify pgrst,'reload schema';
commit;
