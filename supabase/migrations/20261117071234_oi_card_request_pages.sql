create function benchmark_private.oi_list_card_request_page(p_before timestamptz, p_before_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := benchmark_private.oi_actor();
begin
  if (p_before is null) <> (p_before_id is null) then
    raise exception 'invalid_card_request_cursor' using errcode = '22023';
  end if;

  return (
    with page as (
      select receipt, created_at, id
      from benchmark_private.oi_card_request_details
      where owner_id = actor and requester_id <> actor and status = 'pending'
        and (p_before is null or (created_at, id) < (p_before, p_before_id))
      order by created_at desc, id desc
      limit 100
    ), cursor_row as (
      select created_at, id from page order by created_at asc, id asc limit 1
    )
    select jsonb_build_object(
      'items', coalesce(jsonb_agg(page.receipt order by page.created_at desc, page.id desc), '[]'::jsonb),
      'next_before', case when count(*) = 100 then (select created_at::text from cursor_row) end,
      'next_before_id', case when count(*) = 100 then (select id from cursor_row) end
    ) from page
  );
end;
$$;
revoke all on function benchmark_private.oi_list_card_request_page(timestamptz, uuid) from public, anon, authenticated;
grant execute on function benchmark_private.oi_list_card_request_page(timestamptz, uuid) to authenticated;

create function public.oi_card_request_page(p_before timestamptz default null, p_before_id uuid default null)
returns jsonb
language sql security invoker set search_path = '' as $$
  select benchmark_private.oi_list_card_request_page(p_before, p_before_id);
$$;
revoke all on function public.oi_card_request_page(timestamptz, uuid) from public, anon, authenticated;
grant execute on function public.oi_card_request_page(timestamptz, uuid) to authenticated;
