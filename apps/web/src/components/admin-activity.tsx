"use client";
import { useRef, useState } from "react";
import { activityKoreaTime, activityLabels, activityNames, type ActivityRecord } from "@/lib/activity";

type Result = { rows: ActivityRecord[]; next: { cursorTime: string; cursorId: string } | null };
export function AdminActivity() {
  const form = useRef<HTMLFormElement>(null);
  const [mode, setMode] = useState<"day" | "range">("range");
  const [date, setDate] = useState("");
  const [summary, setSummary] = useState("");
  const [result, setResult] = useState<Result | null>(null);
  const [applied, setApplied] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  function resetResults() { setResult(null); setApplied(""); setError(""); }
  function chooseDay(offset = 0) {
    setMode("day");
    setDate(activityKoreaTime(new Date(Date.now() + offset * 86400000).toISOString()).slice(0, 10));
    resetResults();
  }
  function filters() {
    if (!form.current?.reportValidity()) return null;
    const params = new URLSearchParams();
    for (const [key, value] of new FormData(form.current!)) {
      if (typeof value !== "string" || !value.trim()) continue;
      if (key === "from" || key === "to") params.set(key, new Date(`${value}+09:00`).toISOString());
      else params.set(key, value.trim());
    }
    if (params.has("from") && params.has("to") && params.get("from")! >= params.get("to")!) {
      throw new Error("종료 시각은 시작 시각보다 늦게 선택해주세요.");
    }
    return params;
  }
  async function query(next = false) {
    setBusy(true); setError("");
    try {
      const params = next ? new URLSearchParams(applied) : filters();
      if (!params) return;
      if (next && result?.next) for (const [key, value] of Object.entries(result.next)) params.set(key, value);
      const response = await fetch(`/api/admin/activity?${params}`);
      const data = await response.json();
      if (!response.ok) throw new Error(data.error);
      setResult(data);
      if (!next) {
        setApplied(params.toString());
        const showTime = (value: string) => activityKoreaTime(value).slice(0, 16).replace("T", " ");
        setSummary(params.has("date") ? `${params.get("date")} 하루` : `${params.has("from") ? showTime(params.get("from")!) : "최근 30일 시작"} ~ ${params.has("to") ? showTime(params.get("to")!) + " 미만" : "현재"}`);
      }
    } catch (e) { setError(e instanceof Error ? e.message : "로그를 불러오지 못했습니다."); }
    finally { setBusy(false); }
  }
  async function download() {
    setBusy(true); setError("");
    try {
      const params = filters(); if (!params) return; params.set("format", "csv");
      const response = await fetch(`/api/admin/activity?${params}`);
      if (!response.ok) throw new Error((await response.json()).error);
      const url = URL.createObjectURL(await response.blob());
      const link = document.createElement("a"); link.href = url; link.download = mode === "day" && date ? `page-activity-${date}.csv` : "page-activity.csv";
      document.body.appendChild(link); link.click(); link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (e) { setError(e instanceof Error ? e.message : "CSV를 저장하지 못했습니다."); }
    finally { setBusy(false); }
  }
  return <section className="activity-panel" aria-labelledby="activity-title"><h2 id="activity-title">페이지 활동 로그</h2>
    <p className="activity-description">한국 시간(Asia/Seoul) 기준 · 최근 30일 보관</p>
    <form ref={form} onChange={resetResults} onSubmit={e => { e.preventDefault(); void query(); }}><fieldset disabled={busy}>
      <legend className="sr-only">활동 로그 조회 조건</legend>
      <div className="activity-period">
        <div className="activity-mode" role="group" aria-label="조회 방식">
          <button type="button" aria-pressed={mode === "day"} onClick={() => { if (!date) chooseDay(); else { setMode("day"); resetResults(); } }}>일자별</button>
          <button type="button" aria-pressed={mode === "range"} onClick={() => { setMode("range"); resetResults(); }}>기간·시간</button>
        </div>
        <div className="activity-presets" role="group" aria-label="빠른 날짜 선택">
          <button type="button" onClick={() => chooseDay()}>오늘</button>
          <button type="button" onClick={() => chooseDay(-1)}>어제</button>
        </div>
      </div>
      <div hidden={mode !== "day"}>
        <label>조회 일자 (한국 시간)<input name="date" type="date" value={date} required={mode === "day"} disabled={mode !== "day"} onChange={e => setDate(e.target.value)} /></label>
        <small>선택한 날짜의 00:00부터 24:00 직전까지 조회합니다.</small>
      </div>
      <div hidden={mode !== "range"}>
        <div className="activity-filters">
          <label>시작 시각<input name="from" type="datetime-local" disabled={mode !== "range"} /></label>
          <label>종료 시각 (미포함)<input name="to" type="datetime-local" disabled={mode !== "range"} /></label>
        </div>
        <small>비워두면 최근 30일 전체를 조회합니다. 종료 시각의 기록은 포함하지 않습니다.</small>
      </div>
      <div className="activity-filters activity-details">
        <label>이벤트<select name="name"><option value="">전체 이벤트</option>{activityNames.map(name => <option key={name} value={name}>{activityLabels[name]}</option>)}</select></label>
        <label>페이지 경로<input name="path" placeholder="/ 또는 /stories/스토리 UUID" /></label>
        <label>스토리 ID<input name="storyId" placeholder="스토리 UUID" /></label>
      </div>
      <div className="admin-actions activity-actions">
        <button className="button primary" type="submit">{busy ? "처리 중…" : "로그 조회"}</button>
        <button className="button secondary" type="button" onClick={download}>현재 조건으로 CSV 저장</button>
      </div>
    </fieldset></form>
    <p className="activity-description">조회 100건씩 · CSV 최대 5,000건(UTC·한국 시각 포함). 예약 접수와 링크 클릭은 실제 기부 완료를 의미하지 않습니다.</p>
    {error && <p role="alert" className="error-message">{error}</p>}
    {result && <><p className="activity-applied">조회 범위: {summary} · 한국 시간</p><p role="status">{result.rows.length ? `${result.rows.length}건 표시` : "해당 조건의 활동 로그가 없습니다."}</p>
      {!!result.rows.length && <div className="activity-table" tabIndex={0} role="region" aria-label="활동 로그 표"><table><thead><tr><th>발생 시각</th><th>이벤트</th><th>페이지 / 스토리 ID</th><th>속성</th><th>세션 / 방문 ID</th></tr></thead><tbody>{result.rows.map(row => <tr key={row.id}><td>{activityKoreaTime(row.occurred_at).slice(0, 19).replace("T", " ")}</td><td>{activityLabels[row.name]}</td><td>{row.path}{row.story_id && row.path !== `/stories/${row.story_id}` && <><br />{row.story_id}</>}</td><td>{JSON.stringify(row.properties)}</td><td>{row.session_id}<br />{row.visit_id}</td></tr>)}</tbody></table></div>}
      {result.next && <button className="button secondary" type="button" disabled={busy} onClick={() => { void query(true); }}>다음 100건</button>}</>}
  </section>;
}
