begin;

-- Review only reported, already-public notes. The server owns decisions and text.
alter table benchmark_private.oi_building_note_reports
  add column ai_attempts integer not null default 0,
  add column ai_claim uuid,
  add column ai_started_at timestamptz,
  add column ai_completed_at timestamptz;

create function public.oi_moderate_building_note(p_user uuid,p_session uuid,p_report uuid,
  p_claim uuid default null,p_snapshot text default null,p_decision text default null,p_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  actor uuid;
  reporter uuid;
  item benchmark_private.oi_building_notes;
  report benchmark_private.oi_building_note_reports;
  snapshot text;
  claim uuid;
  result_status text;
  explanation text;
begin
  if current_setting('role',true) is distinct from 'service_role' then
    raise exception 'Service role required' using errcode='42501'; end if;
  perform 1 from auth.sessions where id=p_session and user_id=p_user for share;
  if not found then raise exception 'Sign in again' using errcode='PT401'; end if;
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p_user,'session_id',p_session,'role','authenticated')::text,true);
  actor:=benchmark_private.oi_actor();
  select m.account_id into reporter from benchmark_private.oi_building_note_reports r
    join benchmark_private.oi_account_members m on m.auth_user_id=r.reporter_member_id where r.id=p_report;
  if reporter is null or (reporter<>actor and not benchmark_private.oi_is_operator()) then
    raise exception 'Report unavailable' using errcode='42501'; end if;
  -- Same lock order as manual review; a late AI response must not undo an operator decision.
  select n.* into item from benchmark_private.oi_building_notes n
    join benchmark_private.oi_building_note_reports r on r.note_id=n.id where r.id=p_report for update of n;
  select * into report from benchmark_private.oi_building_note_reports where id=p_report for update;
  if not found then raise exception 'Report unavailable' using errcode='PT404'; end if;
  if report.status<>'pending' or item.status<>'published' or report.ai_completed_at is not null then
    return jsonb_build_object('id',p_report,'status',report.status,'ready',false);
  end if;
  snapshot:=encode(sha256(convert_to(jsonb_build_array(item.id,item.body)::text,'UTF8')),'hex');
  if p_claim is null then
    if p_snapshot is not null or p_decision is not null or p_reason is not null then
      raise exception 'Invalid review' using errcode='22023'; end if;
    if report.ai_attempts>=3 or report.ai_started_at>clock_timestamp()-interval '90 seconds' then
      return jsonb_build_object('id',p_report,'status',report.status,'ready',false);
    end if;
    claim:=gen_random_uuid();
    update benchmark_private.oi_building_note_reports set ai_attempts=ai_attempts+1,
      ai_claim=claim,ai_started_at=clock_timestamp() where id=p_report;
    return jsonb_build_object('id',p_report,'status',report.status,'ready',true,
      'claim',claim,'snapshot',snapshot,'body',item.body);
  end if;
  if report.ai_claim is distinct from p_claim or p_snapshot is distinct from snapshot
    or report.ai_started_at<clock_timestamp()-interval '90 seconds' then
    raise exception 'Stale review' using errcode='PT409'; end if;
  if p_decision is null or p_decision not in ('remove','keep','manual_review')
    or (p_decision='remove' and (p_reason is null or p_reason not in
      ('privacy','rights','profanity','harassment','sexual','violence','spam','fraud')))
    or (p_decision<>'remove' and p_reason is not null) then
    raise exception 'Invalid decision' using errcode='22023'; end if;
  result_status:=case p_decision when 'remove' then 'deleted' when 'keep' then 'dismissed' else 'pending' end;
  explanation:=case p_decision
    when 'remove' then 'AI 검토: 명확한 위반으로 삭제 — '||case p_reason
      when 'privacy' then '개인정보' when 'rights' then '권리 침해' when 'profanity' then '욕설'
      when 'harassment' then '괴롭힘·혐오' when 'sexual' then '선정성' when 'violence' then '폭력'
      when 'spam' then '스팸' when 'fraud' then '사기' end
    when 'keep' then 'AI 검토: 명확한 위반 없음 · 글 유지'
    else 'AI 검토: 맥락 확인이 필요해 운영자 검토 대기' end;
  if p_decision='remove' then
    update benchmark_private.oi_building_notes set status='deleted',deleted_at=clock_timestamp() where id=item.id;
  end if;
  update benchmark_private.oi_building_note_reports set status=result_status,review_note=explanation,
    reviewed_at=case when p_decision='manual_review' then null else clock_timestamp() end,
    reviewed_by=null,ai_completed_at=clock_timestamp() where id=p_report;
  insert into benchmark_private.oi_audit(actor_id,action,target_id)
    values(p_user,'building_note_ai:'||p_decision||coalesce(':'||p_reason,''),item.id);
  return jsonb_build_object('id',p_report,'status',result_status,'ready',false);
end;
$$;
revoke all on function public.oi_moderate_building_note(uuid,uuid,uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.oi_moderate_building_note(uuid,uuid,uuid,uuid,text,text,text) to service_role;

notify pgrst,'reload schema';
commit;
