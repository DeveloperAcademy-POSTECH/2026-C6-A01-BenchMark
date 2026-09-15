"use client";
/* eslint-disable @next/next/no-img-element */
import { ActivityTracker } from "./activity-tracker";
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { activityReporter, trackActivity } from "@/lib/activity-client";
import { byteLength } from "@/lib/story";
import { reasons, paymentMethods, reservationInput } from "@/lib/reservation";

export function ReservationForm({ sourceStoryId }: { sourceStoryId?: string }) {
  const [reason, setReason] = useState("");
  const [text, setText] = useState("");
  const [preview, setPreview] = useState("");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState("");
  const requestId = useRef("");
  const locked = useRef(false);
  useEffect(() => () => { if (preview) URL.revokeObjectURL(preview); }, [preview]);
  async function submit(event: React.FormEvent<HTMLFormElement>) {
    const reportActivity = activityReporter();
    event.preventDefault(); if (locked.current) return;
    const form = new FormData(event.currentTarget);
    requestId.current ||= crypto.randomUUID();
    form.set("id", requestId.current);
    if (sourceStoryId) form.set("sourceStoryId", sourceStoryId);
    const parsed = reservationInput.safeParse({ ...Object.fromEntries(form), sourceStoryId });
    if (!parsed.success) { setError(parsed.error.issues[0].message); return; }
    const file = form.get("photo");
    if (!(file instanceof File) || !file.size) { setError("사진 한 장을 올려주세요."); return; }
    if (file.size > 5 * 1024 * 1024) { setError("사진은 5MB 이하로 올려주세요."); return; }
    reportActivity("reservation_attempt");
    locked.current = true; setBusy(true); setError("");
    try {
      const response = await fetch("/api/reservations", { method: "POST", body: form });
      const result = await response.json(); if (!response.ok) throw new Error(result.error);
      reportActivity("reservation_success");
      setDone(true); window.scrollTo({ top: 0, behavior: "instant" });
    } catch (e) { reportActivity("reservation_failure"); setError(e instanceof Error ? e.message : "예약을 접수하지 못했어요. 입력한 내용은 유지됩니다. 다시 시도해주세요."); }
    finally { locked.current = false; setBusy(false); }
  }
  if (done) return <section className="reservation-success"><ActivityTracker storyId={sourceStoryId} /><span className="eyebrow">당신의 마음을 잘 받았어요</span><h1>기부 예약이 접수됐어요.</h1><p>남겨주신 이야기는 운영진이 확인할게요.<br />결제는 진행되지 않았으며,<br />기부 진행 방법은 남겨주신 휴대폰번호로 안내드릴게요.</p><Link href={sourceStoryId ? `/stories/${sourceStoryId}` : "/"} className="button primary">이야기로 돌아가기</Link></section>;
  return <section className="reservation-page"><ActivityTracker storyId={sourceStoryId} /><Link className="back-link" href={sourceStoryId ? `/stories/${sourceStoryId}` : "/"}>← 이야기로 돌아가기</Link><div className="reservation-heading"><span className="eyebrow">다음 사람의 쉼을 위해</span><h1>기부 예약</h1><p>당신의 이야기도 한 자리 펼쳐주세요.<br />지금은 예약만 접수하며 결제는 진행되지 않아요.</p></div>
    <form onSubmit={submit} onChange={() => { requestId.current = ""; }}><fieldset disabled={busy} className="reservation-fields">
      <fieldset className="reservation-question"><legend><span>01</span> 왜 기부 예약을 하시게 되었나요?</legend><div className="reason-options">{Object.entries(reasons).map(([value, label]) => <label key={value}><input type="radio" name="reason" value={value} checked={reason === value} onChange={() => setReason(value)} required />{label}</label>)}</div>{reason === "other" ? <label className="other-reason"><span className="sr-only">기타 이유</span><input name="reasonOther" maxLength={300} placeholder="예약하게 된 이유를 들려주세요" required /></label> : <input type="hidden" name="reasonOther" value="" />}</fieldset>
      <fieldset className="reservation-question"><legend><span>02</span> 성함과 연락처를 남겨주세요</legend><label><span className="sr-only">성함</span><input name="displayName" autoComplete="name" maxLength={40} placeholder="성함" required /></label><label><span className="sr-only">휴대폰번호</span><input name="phone" type="tel" autoComplete="tel" maxLength={20} placeholder="휴대폰번호" required /></label></fieldset>
      <fieldset className="reservation-question"><legend><span>03</span> 돗자리에 남길 스토리를 작성해주세요</legend><label><span className="sr-only">제목</span><input name="title" maxLength={80} placeholder="제목" required /></label><label><span className="sr-only">스토리</span><textarea aria-label="스토리" name="story" value={text} onChange={(e) => setText(e.target.value)} placeholder="당신의 이야기를 들려주세요" rows={5} required aria-describedby="reservation-bytes" /><small id="reservation-bytes" className={`byte-counter ${byteLength(text) > 500 ? "error-message" : ""}`}>{byteLength(text)} / 500바이트</small></label><label className="photo-upload">{preview ? <img src={preview} alt="선택한 사진 미리보기" /> : <span className="photo-upload-copy"><strong>＋</strong>사진 추가<small>JPG, PNG, WebP · 한 장 · 최대 5MB</small></span>}<span className="sr-only">사진 추가</span><input aria-label="사진 추가" name="photo" type="file" accept="image/jpeg,image/png,image/webp" required onChange={(e) => { const file = e.target.files?.[0]; if (file) trackActivity("photo_selected"); setPreview(file ? URL.createObjectURL(file) : ""); }} /></label></fieldset>
      <fieldset className="reservation-question"><legend><span>04</span> 결제방법을 선택해주세요</legend><p className="field-description">나중에 이용하고 싶은 방법을 선택해주세요.</p><div className="payment-options">{Object.entries(paymentMethods).map(([value, label]) => <label key={value}><input type="radio" name="paymentMethod" value={value} required /><span>{label}</span></label>)}</div></fieldset>
      <fieldset className="reservation-question"><legend><span>05</span> 결제예정 금액을 남겨주세요</legend><label className="amount-input"><span className="sr-only">결제예정 금액</span><input name="amount" type="number" inputMode="numeric" min="1" max="2147483647" step="1" placeholder="0" required /><span aria-hidden="true">원</span></label></fieldset>
      {error && <p role="alert" className="error-message">{error}</p>}<button className="button primary reservation-submit" disabled={busy || byteLength(text) > 500}>{busy ? "예약을 접수하는 중…" : "기부 예약 접수하기"}</button><p className="reservation-footnote">운영진 확인 후 기부 진행 방법을 안내드려요.</p>
    </fieldset></form>
  </section>;
}
