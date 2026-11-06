begin;

-- Reports and moderation decisions are private; public clients never read them directly.
create table benchmark_private.oi_content_reports (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null references public.oi_stories(id) on delete cascade,
  reporter_member_id uuid not null references benchmark_private.oi_account_members(auth_user_id) on delete cascade,
  reason text not null check(reason in ('abuse','privacy','sexual','violence','other')),
  detail text not null check(length(detail)<=1000),
  status text not null default 'pending' check(status in ('pending','dismissed','hidden','suspended')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  review_note text check(length(review_note)<=1000),
  unique(story_id,reporter_member_id)
);
create index oi_content_reports_pending on benchmark_private.oi_content_reports(status,created_at);
create table benchmark_private.oi_content_restrictions (
  member_id uuid primary key references benchmark_private.oi_account_members(auth_user_id) on delete cascade,
  active boolean not null default true,
  note text not null check(length(btrim(note)) between 1 and 1000),
  updated_at timestamptz not null default now()
);
alter table benchmark_private.oi_content_reports enable row level security;
alter table benchmark_private.oi_content_restrictions enable row level security;
revoke all on benchmark_private.oi_content_reports,benchmark_private.oi_content_restrictions from public,anon,authenticated;

-- Membership is resolved at read time: merging accounts cannot discard a restriction.
create function benchmark_private.oi_content_restricted(p_account uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from benchmark_private.oi_content_restrictions r
    join benchmark_private.oi_account_members m on m.auth_user_id=r.member_id
    where m.account_id=p_account and r.active);
$$;
revoke all on function benchmark_private.oi_content_restricted(uuid) from public;
grant execute on function benchmark_private.oi_content_restricted(uuid) to anon,authenticated;

create policy oi_content_anonymous_safety on public.oi_stories as restrictive for select to anon
using (not benchmark_private.oi_content_restricted(user_id));

create policy oi_content_public_safety on public.oi_stories as restrictive for select to authenticated
using (not benchmark_private.oi_content_restricted(user_id)
  or user_id=(select benchmark_private.oi_account_id()) or (select benchmark_private.oi_is_operator()));

create function benchmark_private.oi_guard_restricted_story() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  -- Trusted merge/deletion jobs retain their ownership and cleanup operations.
  if auth.uid() is not null and not benchmark_private.oi_is_operator()
    and benchmark_private.oi_content_restricted(new.user_id) and new.status<>'deleted' then
    raise exception 'Content publication restricted; contact support' using errcode='42501';
  end if;
  return new;
end;
$$;
revoke all on function benchmark_private.oi_guard_restricted_story() from public,anon,authenticated;
create trigger oi_restricted_story before insert or update on public.oi_stories
for each row execute function benchmark_private.oi_guard_restricted_story();

-- Security-definer collection RPCs must not bypass moderation through a known ID.
create function benchmark_private.oi_guard_restricted_collection() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is not null and exists(select 1 from public.oi_stories s
    where s.id=new.story_id and benchmark_private.oi_content_restricted(s.user_id)) then
    raise exception 'Story unavailable' using errcode='42501';
  end if;
  return new;
end;
$$;
revoke all on function benchmark_private.oi_guard_restricted_collection() from public,anon,authenticated;
create trigger oi_restricted_collection before insert or update on public.oi_collections
for each row execute function benchmark_private.oi_guard_restricted_collection();
create trigger oi_restricted_card_request before insert or update on benchmark_private.oi_card_requests
for each row execute function benchmark_private.oi_guard_restricted_collection();

create function public.oi_report_content(p_story uuid,p_reason text,p_detail text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=benchmark_private.oi_actor(); report benchmark_private.oi_content_reports; owner_id uuid;
begin
  if p_reason is null or p_reason not in ('abuse','privacy','sexual','violence','other')
    or p_detail is null or length(p_detail)>1000 then raise exception 'Invalid report' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,197));
  select * into report from benchmark_private.oi_content_reports where story_id=p_story and reporter_member_id=auth.uid();
  if found then return jsonb_build_object('id',report.id,'status',report.status); end if;
  select user_id into owner_id from public.oi_stories where id=p_story and status='published' for share;
  if not found or owner_id=actor or benchmark_private.oi_content_restricted(owner_id) then
    raise exception 'Story unavailable' using errcode='42501'; end if;
  if (select count(*) from benchmark_private.oi_content_reports where reporter_member_id=auth.uid() and created_at>now()-interval '1 day')>=20 then
    raise exception 'Too many reports' using errcode='PT429'; end if;
  insert into benchmark_private.oi_content_reports(story_id,reporter_member_id,reason,detail)
    values(p_story,auth.uid(),p_reason,btrim(p_detail)) returning * into report;
  return jsonb_build_object('id',report.id,'status',report.status);
end;
$$;
revoke all on function public.oi_report_content(uuid,text,text) from public,anon,authenticated;
grant execute on function public.oi_report_content(uuid,text,text) to authenticated;

create function public.oi_content_reports(p_offset integer default 0) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  perform benchmark_private.oi_actor();
  if not benchmark_private.oi_is_operator() then raise exception 'Operator required' using errcode='42501'; end if;
  if p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'Invalid offset' using errcode='22023'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(r)),'[]') from (
    select r.id,r.story_id,r.reason,r.detail,r.status,r.created_at,r.review_note,
      s.title,s.body,s.user_id as author_id,benchmark_private.oi_content_restricted(s.user_id) as restricted
    from benchmark_private.oi_content_reports r join public.oi_stories s on s.id=r.story_id
    order by (r.status='pending') desc,r.created_at desc,r.id limit 50 offset p_offset
  ) r);
end;
$$;
revoke all on function public.oi_content_reports(integer) from public,anon,authenticated;
grant execute on function public.oi_content_reports(integer) to authenticated;

create function public.oi_review_content(p_report uuid,p_action text,p_note text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare report benchmark_private.oi_content_reports; story public.oi_stories;
begin
  perform benchmark_private.oi_actor();
  if not benchmark_private.oi_is_operator() then raise exception 'Operator required' using errcode='42501'; end if;
  if p_action is null or p_action not in ('dismissed','hidden','suspended','restore')
    or p_note is null or length(btrim(p_note)) not between 1 and 1000 then
    raise exception 'Invalid decision' using errcode='22023'; end if;
  -- Story then report follows the report/create and deletion lock order.
  select s.* into story from public.oi_stories s join benchmark_private.oi_content_reports r on r.story_id=s.id where r.id=p_report for update of s;
  if not found then raise exception 'Report unavailable' using errcode='PT404'; end if;
  select * into report from benchmark_private.oi_content_reports where id=p_report for update;
  if p_action<>'restore' and report.status<>'pending' then raise exception 'Report already reviewed' using errcode='PT409'; end if;
  if p_action='suspended' then
    if exists(select 1 from benchmark_private.oi_operators o join benchmark_private.oi_account_members m on m.auth_user_id=o.user_id where m.account_id=story.user_id) then
      raise exception 'Operator cannot be restricted here' using errcode='42501'; end if;
    insert into benchmark_private.oi_content_restrictions(member_id,note)
      select auth_user_id,btrim(p_note) from benchmark_private.oi_account_members where account_id=story.user_id
      on conflict(member_id) do update set active=true,note=excluded.note,updated_at=now();
  elsif p_action='restore' then
    update benchmark_private.oi_content_restrictions set active=false,note=btrim(p_note),updated_at=now()
      where member_id in(select auth_user_id from benchmark_private.oi_account_members where account_id=story.user_id);
  end if;
  if p_action in ('hidden','suspended') then
    update public.oi_stories set status='hidden',revision=revision+1,updated_at=now() where id=story.id;
  end if;
  if p_action<>'restore' then
    update benchmark_private.oi_content_reports set status=p_action,reviewed_at=now(),reviewed_by=auth.uid(),review_note=btrim(p_note) where id=p_report;
  end if;
  insert into benchmark_private.oi_audit(actor_id,action,target_id) values(auth.uid(),'content:'||p_action,story.id);
  return jsonb_build_object('id',p_report,'status',p_action);
end;
$$;
revoke all on function public.oi_review_content(uuid,text,text) from public,anon,authenticated;
grant execute on function public.oi_review_content(uuid,text,text) to authenticated;
commit;
