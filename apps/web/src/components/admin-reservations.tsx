"use client";
/* eslint-disable @next/next/no-img-element */
import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { reasons, paymentMethods, type Reservation } from "@/lib/reservation";

export function AdminReservations({ reservations, onSelect }: { reservations: Reservation[]; onSelect: (r: Reservation) => void }) {
  const router = useRouter();
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  async function remove(id: string) {
    setBusy(true); setError("");
    try {
      const response = await fetch(`/api/admin/reservations/${id}`, { method: "DELETE" });
      const result = await response.json(); if (!response.ok) throw new Error(result.error);
      setConfirm(""); router.refresh();
    } catch (e) { setError(e instanceof Error ? e.message : "예약을 삭제하지 못했습니다."); }
    finally { setBusy(false); }
  }
  return <section className="reservation-inbox" aria-labelledby="reservation-inbox-title"><div className="section-heading"><h2 id="reservation-inbox-title">기부 예약 접수함</h2><span className="count">{reservations.length}건</span></div><p className="section-description">예약은 아직 결제된 기부가 아닙니다. 입금과 내용을 확인해주세요.</p>{error && <p className="error-message" role="alert">{error}</p>}
    {reservations.map((r) => <details className="reservation-entry" key={r.id}><summary><span className={`status-badge ${r.story_id ? "public" : ""}`}>{r.story_id ? "이야기 등록됨" : "접수"}</span><strong>{r.display_name} · {r.amount.toLocaleString("ko-KR")}원 예약</strong><span>{r.title}</span></summary><div className="reservation-entry-body"><dl>{r.email && <><dt>이메일</dt><dd><a href={`mailto:${r.email}`}>{r.email}</a></dd></>}{r.phone && <><dt>휴대폰</dt><dd><a href={`tel:${r.phone}`}>{r.phone}</a></dd></>}<dt>예약 이유</dt><dd>{reasons[r.reason]}{r.reason === "other" && ` · ${r.reason_other}`}</dd><dt>희망 결제방법</dt><dd>{paymentMethods[r.payment_method]}</dd><dt>접수일</dt><dd>{new Date(r.created_at).toLocaleString("ko-KR", { timeZone: "Asia/Seoul" })}</dd></dl><img src={`/api/admin/reservations/${r.id}/photo`} alt="예약에 첨부된 사진" loading="lazy" /><h3>{r.title}</h3><p className="reservation-story">{r.story}</p>{r.source_story_id && <Link className="text-link" href={`/stories/${r.source_story_id}`} target="_blank">예약 전 읽은 이야기 ↗</Link>}{!r.story_id ? <button className="button secondary" onClick={() => onSelect(r)}>이 예약으로 이야기 등록</button> : <p className="notice">연결된 이야기는 아래 이야기 목록에서 수정할 수 있습니다.</p>}
    <div className="delete-area">{confirm === r.id ? <><p>연락처와 예약 사진을 포함한 예약 자료를 삭제합니다. 이미 등록한 공개 이야기는 유지됩니다.</p><button disabled={busy} className="danger-button" onClick={() => remove(r.id)}>예약 영구 삭제 확인</button><button disabled={busy} className="text-button" onClick={() => setConfirm("")}>취소</button></> : <button className="danger-button" onClick={() => setConfirm(r.id)}>예약 삭제</button>}</div></div></details>)}
    {!reservations.length && <p className="empty-state">아직 접수된 기부 예약이 없습니다.</p>}
  </section>;
}
