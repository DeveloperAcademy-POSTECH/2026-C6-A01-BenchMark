begin;

-- Building notes are immediately public. Story publication/review is unchanged.
create table benchmark_private.oi_note_buildings (
  id text primary key, name text not null
);
create table benchmark_private.oi_building_notes (
  id uuid primary key,
  building_id text not null references benchmark_private.oi_note_buildings(id),
  author_member_id uuid not null references benchmark_private.oi_account_members(auth_user_id) on delete cascade,
  body text not null check(length(btrim(body)) between 1 and 140),
  status text not null default 'published' check(status in ('published','deleted')),
  created_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz
);
create index oi_building_notes_page on benchmark_private.oi_building_notes(building_id,created_at desc,id desc) where status='published';
create index oi_building_notes_author on benchmark_private.oi_building_notes(author_member_id,created_at);
create table benchmark_private.oi_building_note_reports (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null references benchmark_private.oi_building_notes(id) on delete cascade,
  reporter_member_id uuid not null references benchmark_private.oi_account_members(auth_user_id) on delete cascade,
  reason text not null check(reason in ('abuse','privacy','sexual','violence','other')),
  detail text not null check(length(detail)<=1000),
  status text not null default 'pending' check(status in ('pending','dismissed','deleted')),
  created_at timestamptz not null default clock_timestamp(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  review_note text,
  unique(note_id,reporter_member_id)
);
create index oi_building_note_reports_queue on benchmark_private.oi_building_note_reports(status,created_at);
alter table benchmark_private.oi_note_buildings enable row level security;
alter table benchmark_private.oi_building_notes enable row level security;
alter table benchmark_private.oi_building_note_reports enable row level security;
revoke all on benchmark_private.oi_note_buildings,benchmark_private.oi_building_notes,benchmark_private.oi_building_note_reports from public,anon,authenticated;

-- Stable IDs from the bundled POSTECH building catalog.
insert into benchmark_private.oi_note_buildings(id,name) values
('135973462','포스코국제관'),
('135973505','학생회관'),
('136173360','지곡회관'),
('136179047','POSPLEX'),
('136182168','박태준학술정보관'),
('136186601','바이오오픈이노베이션센터'),
('136187755','남자 기숙사 14'),
('136187756','남자 기숙사 11'),
('136187757','남자 기숙사 10'),
('136187758','남자 기숙사 9'),
('136187759','남자 기숙사 19'),
('136187761','남자 기숙사 15'),
('136187867','기숙사 16 DICE'),
('136187868','남자 기숙사 13'),
('136188127','남자 기숙사 17'),
('136188129','남자 기숙사 12'),
('136188643','제4공학관'),
('136188879','대강당'),
('136188882','제5공학관'),
('136188883','제2공학관'),
('136188886','제3공학관'),
('136188887','수리과학관'),
('136188889','무은재기념관'),
('136189133','대학본부'),
('136189135','제1공학관'),
('136189136','포항산업과학연구원 연구4동'),
('136240952','기숙사 20동'),
('136242421','남자 기숙사 18'),
('136242801','여자 기숙사 1'),
('136242803','여자 기숙사 2'),
('136242805','여자 기숙사 3'),
('136242911','기숙사 21동'),
('136242966','남자 기숙사 2'),
('136242984','남자 기숙사 4'),
('136242985','남자 기숙사 1'),
('136242986','남자 기숙사 3'),
('136243002','남자 기숙사 5'),
('136243003','남자 기숙사 7'),
('136243004','남자 기숙사 6'),
('136243005','남자 기숙사 8'),
('136243064','대학원생 아파트 1동'),
('136243065','대학원생 아파트 2동'),
('136243081','대학원생 아파트 3동'),
('136243098','대학원생 아파트 4동'),
('136961597','인공지능연구원'),
('136961695','LG연구동'),
('136961730','환경공학동'),
('136961786','포항산업과학연구원 관리동'),
('136961863','대학체육관'),
('137108894','posville 2'),
('137109024','posville 1'),
('137109025','posville 5'),
('137109125','지곡연구동'),
('137109713','한국로봇융합연구원'),
('137110020','포스텍 철강대학원'),
('191380905','Pohang Accelerator Lab'),
('294906154','포항산업과학연구원 연구1동'),
('294906155','포항산업과학연구원 연구2동'),
('294906156','포항산업과학연구원 연구3동'),
('333372710','포항4세대방사광가속기'),
('353251166','포항금속소재산업진흥원'),
('397201294','C5'),
('628732512','생명공학연구센터'),
('631011000','화학관'),
('631011001','생명과학관'),
('631011002','제1실험동'),
('631011003','기계공작동'),
('631011004','제2실험동'),
('631011005','기계실험동'),
('631011007','풍동동'),
('631011008','RIST 실험동'),
('631011010','RIST 실험동'),
('631011012','RIST 실험동'),
('631011014','RIST 실험동'),
('631011016','RIST 실험동'),
('631011018','RIST 실험동'),
('631011019','RIST 실험동'),
('631011021','RIST 실험동'),
('639992759','나노융합기술원'),
('639992760','연구2동'),
('639992761','연구1동,행정동'),
('639992762','선형가속기동'),
('639992763','EUV가속기동'),
('639992764','154KV변전실'),
('639992765','동력동'),
('942763731','체인지업그라운드'),
('1153267135','포항산업과학연구원 식당'),
('supp-437','기초과학연구원(IBS) 포스텍 캠퍼스'),
('supp-52','첨단기술사업화센터(FABⅡ)');

create function benchmark_private.oi_building_note_json(p_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',n.id,'building_id',n.building_id,'author_id',m.account_id,
    'body',n.body,'created_at',n.created_at,'nickname',p.nickname,
    'admission_year',p.admission_year,'department',p.department)
  from benchmark_private.oi_building_notes n
  join benchmark_private.oi_account_members m on m.auth_user_id=n.author_member_id
  join public.oi_profiles p on p.id=m.account_id
  where n.id=p_id;
$$;
revoke all on function benchmark_private.oi_building_note_json(uuid) from public,anon,authenticated;

create function public.oi_building_notes(p_building text,p_before timestamptz default null,p_before_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not exists(select 1 from benchmark_private.oi_note_buildings where id=p_building)
    or (p_before is null)<>(p_before_id is null) then raise exception 'Invalid building or cursor' using errcode='22023'; end if;
  return (select coalesce(jsonb_agg(benchmark_private.oi_building_note_json(n.id) order by n.created_at desc,n.id desc),'[]') from (
    select n.id,n.created_at from benchmark_private.oi_building_notes n
    join benchmark_private.oi_account_members m on m.auth_user_id=n.author_member_id
    where n.building_id=p_building and n.status='published'
      and not benchmark_private.oi_content_restricted(m.account_id)
      and not benchmark_private.oi_account_is_deleting(m.account_id)
      and (p_before is null or (n.created_at,n.id)<(p_before,p_before_id))
    order by n.created_at desc,n.id desc limit 50
  ) n);
end;
$$;
revoke all on function public.oi_building_notes(text,timestamptz,uuid) from public,anon,authenticated;
grant execute on function public.oi_building_notes(text,timestamptz,uuid) to anon,authenticated;

create function public.oi_post_building_note(p_id uuid,p_building text,p_body text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=benchmark_private.oi_actor(); existing benchmark_private.oi_building_notes;
begin
  if p_id is null or p_body is null or length(btrim(p_body,E' \n\r\t')) not between 1 and 140
    or not exists(select 1 from benchmark_private.oi_note_buildings where id=p_building) then
    raise exception 'Invalid note' using errcode='22023'; end if;
  if benchmark_private.oi_content_restricted(actor) then raise exception 'Writing restricted' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(actor::text,5917));
  select * into existing from benchmark_private.oi_building_notes where id=p_id;
  if found then
    if not exists(select 1 from benchmark_private.oi_account_members where auth_user_id=existing.author_member_id and account_id=actor)
      or existing.building_id<>p_building or existing.body<>btrim(p_body,E' \n\r\t') or existing.status<>'published' then
      raise exception 'Note conflict' using errcode='PT409'; end if;
    return benchmark_private.oi_building_note_json(p_id);
  end if;
  -- Technical abuse limits apply to every member of a merged account.
  if (select count(*) from benchmark_private.oi_building_notes n join benchmark_private.oi_account_members m
    on m.auth_user_id=n.author_member_id where m.account_id=actor and n.created_at>now()-interval '1 day')>=50
    or exists(select 1 from benchmark_private.oi_building_notes n join benchmark_private.oi_account_members m
      on m.auth_user_id=n.author_member_id where m.account_id=actor and n.created_at>clock_timestamp()-interval '5 seconds') then
    raise exception 'Too many notes' using errcode='PT429'; end if;
  insert into benchmark_private.oi_building_notes(id,building_id,author_member_id,body)
    values(p_id,p_building,auth.uid(),btrim(p_body,E' \n\r\t'));
  return benchmark_private.oi_building_note_json(p_id);
end;
$$;
revoke all on function public.oi_post_building_note(uuid,text,text) from public,anon,authenticated;
grant execute on function public.oi_post_building_note(uuid,text,text) to authenticated;

create function public.oi_delete_building_note(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=benchmark_private.oi_actor(); item benchmark_private.oi_building_notes;
begin
  select n.* into item from benchmark_private.oi_building_notes n
    join benchmark_private.oi_account_members m on m.auth_user_id=n.author_member_id
    where n.id=p_id and m.account_id=actor for update of n;
  if not found then raise exception 'Note unavailable' using errcode='42501'; end if;
  update benchmark_private.oi_building_notes set status='deleted',deleted_at=coalesce(deleted_at,now()) where id=p_id;
  return jsonb_build_object('id',p_id,'status','deleted');
end;
$$;
revoke all on function public.oi_delete_building_note(uuid) from public,anon,authenticated;
grant execute on function public.oi_delete_building_note(uuid) to authenticated;

create function public.oi_report_building_note(p_note uuid,p_reason text,p_detail text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=benchmark_private.oi_actor(); report benchmark_private.oi_building_note_reports; owner_id uuid;
begin
  if p_reason is null or p_reason not in ('abuse','privacy','sexual','violence','other') or p_detail is null or length(p_detail)>1000 then
    raise exception 'Invalid report' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(actor::text,5918));
  select r.* into report from benchmark_private.oi_building_note_reports r
    join benchmark_private.oi_account_members m on m.auth_user_id=r.reporter_member_id
    where r.note_id=p_note and m.account_id=actor limit 1;
  if found then return jsonb_build_object('id',report.id,'status',report.status); end if;
  select m.account_id into owner_id from benchmark_private.oi_building_notes n
    join benchmark_private.oi_account_members m on m.auth_user_id=n.author_member_id
    where n.id=p_note and n.status='published' for share of n;
  if not found or owner_id=actor or benchmark_private.oi_content_restricted(owner_id)
    or benchmark_private.oi_account_is_deleting(owner_id) then raise exception 'Note unavailable' using errcode='42501'; end if;
  if (select count(*) from benchmark_private.oi_building_note_reports r join benchmark_private.oi_account_members m
    on m.auth_user_id=r.reporter_member_id where m.account_id=actor and r.created_at>now()-interval '1 day')>=20 then
    raise exception 'Too many reports' using errcode='PT429'; end if;
  insert into benchmark_private.oi_building_note_reports(note_id,reporter_member_id,reason,detail)
    values(p_note,auth.uid(),p_reason,btrim(p_detail)) returning * into report;
  return jsonb_build_object('id',report.id,'status',report.status);
end;
$$;
revoke all on function public.oi_report_building_note(uuid,text,text) from public,anon,authenticated;
grant execute on function public.oi_report_building_note(uuid,text,text) to authenticated;

create function public.oi_building_note_reports(p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  perform benchmark_private.oi_actor();
  if not benchmark_private.oi_is_operator() then raise exception 'Operator required' using errcode='42501'; end if;
  if p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'Invalid offset' using errcode='22023'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(r)),'[]') from (
    select r.id,r.note_id,r.reason,r.detail,r.status,r.review_note,n.body,b.name as building_name,n.status as note_status
    from benchmark_private.oi_building_note_reports r join benchmark_private.oi_building_notes n on n.id=r.note_id
    join benchmark_private.oi_note_buildings b on b.id=n.building_id
    order by (r.status='pending') desc,r.created_at desc,r.id limit 50 offset p_offset
  ) r);
end;
$$;
revoke all on function public.oi_building_note_reports(integer) from public,anon,authenticated;
grant execute on function public.oi_building_note_reports(integer) to authenticated;

create function public.oi_review_building_note(p_report uuid,p_action text,p_note text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare item benchmark_private.oi_building_notes; report benchmark_private.oi_building_note_reports;
begin
  perform benchmark_private.oi_actor();
  if not benchmark_private.oi_is_operator() then raise exception 'Operator required' using errcode='42501'; end if;
  if p_action is null or p_action not in ('dismissed','deleted') or p_note is null or length(btrim(p_note)) not between 1 and 1000 then
    raise exception 'Invalid review' using errcode='22023'; end if;
  select n.* into item from benchmark_private.oi_building_notes n join benchmark_private.oi_building_note_reports r
    on r.note_id=n.id where r.id=p_report for update of n;
  if not found then raise exception 'Report unavailable' using errcode='PT404'; end if;
  select * into report from benchmark_private.oi_building_note_reports where id=p_report for update;
  if report.status<>'pending' then raise exception 'Already reviewed' using errcode='PT409'; end if;
  if p_action='deleted' then
    update benchmark_private.oi_building_notes set status='deleted',deleted_at=coalesce(deleted_at,now()) where id=item.id;
  end if;
  update benchmark_private.oi_building_note_reports set status=p_action,reviewed_at=now(),reviewed_by=auth.uid(),review_note=btrim(p_note)
    where id=p_report;
  insert into benchmark_private.oi_audit(actor_id,action,target_id) values(auth.uid(),'building_note:'||p_action,item.id);
  return jsonb_build_object('id',p_report,'status',p_action);
end;
$$;
revoke all on function public.oi_review_building_note(uuid,text,text) from public,anon,authenticated;
grant execute on function public.oi_review_building_note(uuid,text,text) to authenticated;
commit;
