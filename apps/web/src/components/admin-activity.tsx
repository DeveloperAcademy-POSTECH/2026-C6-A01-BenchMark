"use client";
import { useRef, useState } from "react";
import { activityLabels, activityNames, type ActivityRecord } from "@/lib/activity";

type Result = { rows: ActivityRecord[]; next: { cursorTime: string; cursorId: string } | null };
export function AdminActivity() {
  const form = useRef<HTMLFormElement>(null);
  const [result, setResult] = useState<Result | null>(null);
  const [applied, setApplied] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  function filters() {
    const params = new URLSearchParams();
    for (const [key, value] of new FormData(form.current!)) {
      if (typeof value !== "string" || !value.trim()) continue;
      if (key === "from" || key === "to") params.set(key, new Date(value).toISOString());
      else params.set(key, value.trim());
    }
    return params;
  }
  async function query(next = false) {
    setBusy(true); setError("");
    try {
      const params = next ? new URLSearchParams(applied) : filters();
      if (next && result?.next) for (const [key, value] of Object.entries(result.next)) params.set(key, value);
      const response = await fetch(`/api/admin/activity?${params}`);
      const data = await response.json();
      if (!response.ok) throw new Error(data.error);
      setResult(data); if (!next) setApplied(params.toString());
    } catch (e) { setError(e instanceof Error ? e.message : "로그를 불러오지 못했습니다."); }
    finally { setBusy(false); }
  }
  async function download() {
    setBusy(true); setError("");
    try {
      const params = filters(); params.set("format", "csv");
      const response = await fetch(`/api/admin/activity?${params}`);
      if (!response.ok) throw new Error((await response.json()).error);
      const url = URL.createObjectURL(await response.blob());
      const link = document.createElement("a"); link.href = url; link.download = "page-activity.csv";
      document.body.appendChild(link); link.click(); link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (e) { setError(e instanceof Error ? e.message : "CSV를 저장하지 못했습니다."); }
    finally { setBusy(false); }
  }
  return <section className="activity-panel" aria-labelledby="activity-title"><h2 id="activity-title">페이지 활동 로그</h2>
    <p>최근 30일 · 조회는 100건씩, CSV 저장은 최대 5,000건입니다. 예약 접수와 링크 클릭은 실제 기부 완료를 의미하지 않습니다.</p>
    <form ref={form} onSubmit={e => { e.preventDefault(); void query(); }}><fieldset disabled={busy}>
      <div className="activity-filters"><label>시작 시각<input name="from" type="datetime-local" /></label><label>종료 시각 (미포함)<input name="to" type="datetime-local" /></label>
        <label>이벤트<select name="name"><option value="">전체</option>{activityNames.map(name => <option key={name} value={name}>{activityLabels[name]}</option>)}</select></label>
        <label>페이지 경로<input name="path" placeholder="/ 또는 /stories/스토리 UUID" /></label><label>스토리 ID<input name="storyId" placeholder="스토리 UUID" /></label></div>
      <div className="admin-actions"><button className="button secondary" type="submit">{busy ? "처리 중…" : "로그 조회"}</button><button className="button secondary" type="button" onClick={download}>현재 조건으로 CSV 저장</button></div>
    </fieldset></form>
    <p><small>입력·표시는 브라우저 현지 시간, CSV 시각은 UTC입니다. 조건을 바꾼 뒤 로그 조회를 눌러주세요.</small></p>
    {error && <p role="alert" className="error-message">{error}</p>}
    {result && <><p role="status">{result.rows.length ? `${result.rows.length}건 표시` : "해당 조건의 활동 로그가 없습니다."}</p>
      {!!result.rows.length && <div className="activity-table" tabIndex={0} role="region" aria-label="활동 로그 표"><table><thead><tr><th>발생 시각</th><th>이벤트</th><th>페이지 / 스토리 ID</th><th>속성</th><th>세션 / 방문 ID</th></tr></thead><tbody>{result.rows.map(row => <tr key={row.id}><td>{new Date(row.occurred_at).toLocaleString("ko-KR")}</td><td>{activityLabels[row.name]}</td><td>{row.path}{row.story_id && row.path !== `/stories/${row.story_id}` && <><br />{row.story_id}</>}</td><td>{JSON.stringify(row.properties)}</td><td>{row.session_id}<br />{row.visit_id}</td></tr>)}</tbody></table></div>}
      {result.next && <button className="button secondary" type="button" disabled={busy} onClick={() => { void query(true); }}>다음 100건</button>}</>}
  </section>;
}
