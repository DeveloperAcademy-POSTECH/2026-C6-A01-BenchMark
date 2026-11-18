begin;

-- #504: one like per account and story. The table is private; the app only uses the two RPCs below.
create table benchmark_private.oi_story_likes (
  story_id uuid not null references public.oi_stories(id) on delete cascade,
  account_id uuid not null references public.oi_profiles(id) on delete cascade,
  created_at timestamptz not null default clock_timestamp(),
  primary key (story_id, account_id)
);
create index oi_story_likes_account on benchmark_private.oi_story_likes (account_id);
alter table benchmark_private.oi_story_likes enable row level security;
revoke all on benchmark_private.oi_story_likes from public,anon,authenticated;

-- A story is likeable/countable only while it is publicly visible.
create function benchmark_private.oi_story_likeable(p_story uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.oi_stories s where s.id=p_story and s.status='published'
    and not benchmark_private.oi_content_restricted(s.user_id));
$$;
revoke all on function benchmark_private.oi_story_likeable(uuid) from public,anon,authenticated,service_role;

-- Counts for up to 200 public stories. `liked` is true only for a signed-in caller's own like.
create function public.oi_story_likes(p_stories uuid[]) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor uuid;
begin
  if cardinality(p_stories)>200 then
    raise exception 'Too many stories' using errcode='22023';
  end if;
  if current_setting('role',true) in ('authenticated','service_role') then
    actor:=benchmark_private.oi_account_id();
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('story_id',s.id,
      'count',(select count(*) from benchmark_private.oi_story_likes l where l.story_id=s.id),
      'liked',actor is not null and exists(select 1 from benchmark_private.oi_story_likes l
        where l.story_id=s.id and l.account_id=actor))),'[]'::jsonb)
    from public.oi_stories s
    where s.id=any(p_stories) and benchmark_private.oi_story_likeable(s.id));
end;
$$;
revoke all on function public.oi_story_likes(uuid[]) from public;
grant execute on function public.oi_story_likes(uuid[]) to anon,authenticated;

-- Idempotent set/unset, so a retry or a double tap can never count twice.
create function public.oi_set_story_like(p_story uuid,p_liked boolean) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=benchmark_private.oi_actor(); total bigint;
begin
  if p_liked is null then raise exception 'Invalid like' using errcode='22023'; end if;
  perform 1 from public.oi_stories s where s.id=p_story for share;
  if p_liked then
    if not benchmark_private.oi_story_likeable(p_story) then
      raise exception 'Story unavailable' using errcode='22023';
    end if;
    insert into benchmark_private.oi_story_likes(story_id,account_id) values (p_story,actor)
      on conflict do nothing;
  else
    delete from benchmark_private.oi_story_likes where story_id=p_story and account_id=actor;
  end if;
  select count(*) into total from benchmark_private.oi_story_likes where story_id=p_story;
  return jsonb_build_object('story_id',p_story,'count',total,'liked',p_liked);
end;
$$;
revoke all on function public.oi_set_story_like(uuid,boolean) from public,anon;
grant execute on function public.oi_set_story_like(uuid,boolean) to authenticated;

commit;
