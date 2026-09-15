"use client";
/* eslint-disable @next/next/no-img-element */
import Link from "next/link";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { sizes, byteLength, type Story } from "@/lib/story";
import type { Reservation } from "@/lib/reservation";
import { AdminActivity } from "./admin-activity";
import { AdminReservations } from "./admin-reservations";

function StoryEditor({ story, reservation, onClose }: { story?: Story; reservation?: Reservation; onClose: () => void }) {
  const router = useRouter();
  const [name, setName] = useState(story?.display_name || reservation?.display_name || "");
  const [text, setText] = useState(story?.story || reservation?.story || "");
  const [verified, setVerified] = useState(story?.payment_verified || false);
  const [published, setPublished] = useState(story?.published || false);
  const [preview, setPreview] = useState("");
  const [busy, setBusy] = useState(false); const [error, setError] = useState("");
  const [confirmDelete, setConfirmDelete] = useState(false);
  useEffect(() => () => { if (preview) URL.revokeObjectURL(preview); }, [preview]);
  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError("");
    const data = new FormData(event.currentTarget);
    data.set("paymentVerified", String(verified)); data.set("published", String(published));
    if (story) data.set("revision", String(story.revision));
    if (reservation) data.set("reservationId", reservation.id);
    try {
      const response = await fetch(story ? `/api/admin/stories/${story.id}` : "/api/admin/stories", { method: story ? "PUT" : "POST", body: data });
      const result = await response.json(); if (!response.ok) throw new Error(result.error);
      onClose(); router.refresh();
    } catch (e) { setError(e instanceof Error ? e.message : "저장하지 못했습니다."); }
    finally { setBusy(false); }
  }
  async function remove() {
    if (!story) return; setBusy(true); setError("");
    try {
      const response = await fetch(`/api/admin/stories/${story.id}`, { method: "DELETE", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ revision: story.revision }) });
      const result = await response.json(); if (!response.ok) throw new Error(result.error);
      onClose(); router.refresh();
    } catch (e) { setError(e instanceof Error ? e.message : "삭제하지 못했습니다."); }
    finally { setBusy(false); }
  }
  return <section className="editor" aria-labelledby="editor-title"><div className="section-heading"><h2 id="editor-title">{story ? "이야기 수정" : "새 이야기 등록"}</h2><button type="button" className="text-button" onClick={onClose} disabled={busy}>닫기</button></div><form onSubmit={save}><fieldset disabled={busy}>
    <div className="form-row"><label>돗자리 번호<input name="matNumber" type="number" min="1" max="10000" defaultValue={story?.mat_number} required /></label><label>돗자리 종류<select name="matSize" defaultValue={story?.mat_size || "small"}><option value="small">2~3인용</option><option value="large">4~5인용</option></select></label></div>
    <label>공개 이름<input name="displayName" value={name} onChange={(e) => setName(e.target.value)} maxLength={40} required /></label>
    <label>제목<input name="title" defaultValue={story?.title || reservation?.title || ""} maxLength={80} /></label>
    <label>사진 한 장<input name="photo" type="file" accept="image/jpeg,image/png,image/webp" required={!story && !reservation} onChange={(e) => { const file = e.target.files?.[0]; setPreview(file ? URL.createObjectURL(file) : ""); }} /><small>JPG, PNG, WebP · 최대 5MB. {story && "새 사진을 선택하지 않으면 기존 사진을 유지합니다."}</small></label>
    <label>이야기<textarea name="story" value={text} onChange={(e) => setText(e.target.value)} rows={4} required aria-describedby="story-length" /><small id="story-length" className={byteLength(text) > 500 ? "error-message" : ""}>{byteLength(text)} / 500바이트</small></label>
    <div className="review-checks"><label><input type="checkbox" checked={verified} onChange={(e) => { setVerified(e.target.checked); if (!e.target.checked) setPublished(false); }} /> 입금 확인 완료</label><label><input type="checkbox" checked={published} disabled={!verified} onChange={(e) => setPublished(e.target.checked)} /> 내용 검토 완료 · 웹에 공개</label></div>
    <details className="preview-panel"><summary>공개 내용 미리보기</summary>{(preview || story || reservation) && <img src={preview || (reservation ? `/api/admin/reservations/${reservation.id}/photo` : `/api/stories/${story!.id}/photo?v=${story!.revision}`)} alt="공개할 사진 미리보기" />}<h3>{name || "공개 이름"}님의 이야기</h3><p>{text || "작성한 이야기가 여기에 표시됩니다."}</p></details>
    {error && <p className="error-message" role="alert">{error}</p>}<button className="button primary" disabled={busy || byteLength(text) > 500}>{busy ? "처리 중…" : published ? "저장하고 공개" : "비공개로 저장"}</button>
    {story && <div className="delete-area">{confirmDelete ? <><p>사진과 공감을 포함해 영구 삭제합니다. 되돌릴 수 없습니다.</p><button type="button" className="danger-button" onClick={remove}>영구 삭제 확인</button><button type="button" className="text-button" onClick={() => setConfirmDelete(false)}>취소</button></> : <button type="button" className="danger-button" onClick={() => setConfirmDelete(true)}>이야기 삭제</button>}</div>}
  </fieldset></form></section>;
}
export function AdminDashboard({ stories, reservations }: { stories: Story[]; reservations: Reservation[] }) {
  const [reservation, setReservation] = useState<Reservation | undefined>();
  const router = useRouter(); const [selection, setSelection] = useState<Story | "new" | null>(null);
  const [filter, setFilter] = useState("all"); const [query, setQuery] = useState(""); const [error, setError] = useState("");
  async function logout() {
    try { const result = await fetch("/api/admin/session", { method: "DELETE" }); if (!result.ok) throw new Error(); router.refresh(); }
    catch { setError("로그아웃하지 못했습니다. 다시 시도해주세요."); }
  }
  const visible = stories.filter((s) => (filter === "all" || (filter === "public" ? s.published : !s.published)) && `${s.mat_number} ${s.display_name}`.includes(query));
  return <div className="admin-page"><div className="section-heading"><div><span className="eyebrow">쉼, 펴 운영팀</span><h1>이야기 관리</h1></div><button className="text-button" onClick={logout}>로그아웃</button></div><p>접수된 기부 예약을 확인하고, 입금과 이야기를 검토한 뒤 공개해주세요.</p>
    <div className="admin-summary"><span>등록 <strong>{stories.length}</strong></span><span>공개 <strong>{stories.filter((s) => s.published).length}</strong></span><span>검토 대기 <strong>{stories.filter((s) => !s.published).length}</strong></span><span>돗자리 목표 <strong>100개</strong></span></div>
    <button className="button primary" onClick={() => { setReservation(undefined); setSelection("new"); }}>+ 새 이야기 등록</button>{error && <p role="alert" className="error-message">{error}</p>}
    {selection !== null && <StoryEditor key={selection === "new" ? reservation?.id || "new" : selection.id} story={selection === "new" ? undefined : selection} reservation={reservation} onClose={() => { setSelection(null); setReservation(undefined); }} />}
    <AdminReservations reservations={reservations} onSelect={(r) => { setReservation(r); setSelection("new"); window.scrollTo({ top: 180, behavior: "instant" }); }} />
    <AdminActivity />
    <div className="admin-filters"><label><span className="sr-only">이름 또는 돗자리 번호 검색</span><input type="search" placeholder="이름 또는 돗자리 번호 검색" value={query} onChange={(e) => setQuery(e.target.value)} /></label><label><span className="sr-only">공개 상태</span><select value={filter} onChange={(e) => setFilter(e.target.value)}><option value="all">전체</option><option value="public">공개</option><option value="private">검토 대기</option></select></label></div>
    <div className="admin-list">{visible.map((s) => <article key={s.id}><div><span className={`status-badge ${s.published ? "public" : ""}`}>{s.published ? "공개" : "비공개"}</span><h2>#{String(s.mat_number).padStart(3, "0")} · {s.display_name}</h2><p>{sizes[s.mat_size].label} · {s.payment_verified ? "입금 확인" : "입금 미확인"} · 공감 {s.reaction_count}</p><p className="admin-story-text">{s.story}</p></div><div className="admin-actions"><button className="button secondary" onClick={() => { setReservation(undefined); setSelection(s); window.scrollTo({ top: 180, behavior: "instant" }); }}>수정·검토</button>{s.published && <Link className="text-link" href={`/stories/${s.id}`} target="_blank">공개 페이지 ↗</Link>}</div></article>)}{!visible.length && <p className="empty-state">표시할 이야기가 없습니다.</p>}</div>
  </div>;
}
