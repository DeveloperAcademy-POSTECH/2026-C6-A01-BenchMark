"use client";
/* eslint-disable @next/next/no-img-element */
import { ActivityTracker } from "./activity-tracker";
import { useEffect, useRef, useState } from "react";
import { activityReporter, trackActivity } from "@/lib/activity-client";
import { byteLength, STORY_MAX_BYTES } from "@/lib/story";
import { reasons, paymentMethods, reservationAmounts, reservationDetailsInput, reservationInput } from "@/lib/reservation";

export function ReservationForm({ sourceStoryId }: { sourceStoryId?: string }) {
  const [isAnonymous, setIsAnonymous] = useState(false);
  const [displayName, setDisplayName] = useState("");
  const [reason, setReason] = useState("");
  const [text, setText] = useState("");
  const [preview, setPreview] = useState("");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState("");
  const [reasonError, setReasonError] = useState("");
  const mainForm = useRef<HTMLFormElement>(null);
  const reasonDialog = useRef<HTMLDialogElement>(null);
  const requestId = useRef("");
  const locked = useRef(false);
  useEffect(() => () => { if (preview) URL.revokeObjectURL(preview); }, [preview]);
  function details() {
    const form = new FormData(mainForm.current!);
    if (sourceStoryId) form.set("sourceStoryId", sourceStoryId);
    const parsed = reservationDetailsInput.safeParse({ ...Object.fromEntries(form), sourceStoryId });
    if (!parsed.success) throw new Error(parsed.error.issues[0].message);
    const file = form.get("photo");
    if (!(file instanceof File) || !file.size) throw new Error("사진 한 장을 올려주세요.");
    if (file.size > 5 * 1024 * 1024) throw new Error("사진은 5MB 이하로 올려주세요.");
    return form;
  }
  function askReason(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (locked.current || reasonDialog.current?.open) return;
    setError(""); setReasonError("");
    try {
      details();
      reasonDialog.current?.showModal();
      trackActivity("reservation_reason_opened");
    } catch (e) { setError(e instanceof Error ? e.message : "입력 내용을 확인해주세요."); }
  }
  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (locked.current) return;
    const reportActivity = activityReporter();
    let form: FormData;
    try {
      form = details();
      for (const [key, value] of new FormData(event.currentTarget)) form.set(key, value);
      requestId.current ||= crypto.randomUUID();
      form.set("id", requestId.current);
      const parsed = reservationInput.safeParse({ ...Object.fromEntries(form), sourceStoryId });
      if (!parsed.success) throw new Error(parsed.error.issues[0].message);
    } catch (e) { setReasonError(e instanceof Error ? e.message : "예약 이유를 확인해주세요."); return; }
    reportActivity("reservation_attempt");
    locked.current = true; setBusy(true); setReasonError("");
    try {
      const response = await fetch("/api/reservations", { method: "POST", body: form });
      const result = await response.json(); if (!response.ok) throw new Error(result.error);
      reportActivity("reservation_success");
      reasonDialog.current?.close();
      setDone(true); window.scrollTo({ top: 0, behavior: "instant" });
    } catch (e) { reportActivity("reservation_failure"); setReasonError(e instanceof Error ? e.message : "예약을 접수하지 못했어요. 입력한 내용은 유지됩니다. 다시 시도해주세요."); }
    finally { locked.current = false; setBusy(false); }
  }
  if (done) return <section className="reservation-success"><ActivityTracker storyId={sourceStoryId} /><span className="eyebrow">당신의 마음을 잘 받았어요</span><h1>기부 예약이 접수됐어요.</h1><p>남겨주신 이야기는 운영진이 확인할게요.<br />결제는 진행되지 않았어요.</p><a href={sourceStoryId ? `/stories/${sourceStoryId}` : "/"} className="button primary">이야기로 돌아가기</a></section>;
  return <section className="reservation-page"><ActivityTracker storyId={sourceStoryId} /><a className="back-link" href={sourceStoryId ? `/stories/${sourceStoryId}` : "/"}>← 이야기로 돌아가기</a><div className="reservation-heading"><span className="eyebrow">다음 사람의 쉼을 위해</span><h1>기부 예약</h1><p>당신의 이야기도 한 자리 펼쳐주세요.<br />지금은 예약만 접수하며 결제는 진행되지 않아요.</p></div>
    <form ref={mainForm} onSubmit={askReason} onChange={() => { requestId.current = ""; }}><fieldset disabled={busy} className="reservation-fields">
      <fieldset className="reservation-question"><legend><span>01</span> 돗자리에 남길 이야기를 들려주세요</legend><div id="story-guidance" className="story-guidance"><p>어떤 이야기를 담을지 고민된다면 아래 질문을 천천히 떠올려보세요. 꼭 질문에 맞추지 않아도 괜찮아요.</p><ul><li>고마움을 전하거나 기억하고 싶은 대상이 있나요?</li><li>다른 사람들과 나누고 싶은 나만의 이야기가 있나요?</li><li>이 돗자리를 펼칠 사람에게 어떤 마음을 건네고 싶나요?</li></ul></div><label><span className="sr-only">마음을 담은 한 줄</span><input name="title" maxLength={80} placeholder="마음을 담은 한 줄" required /></label><label><span className="sr-only">스토리</span><textarea aria-label="스토리" name="story" value={text} onChange={(e) => setText(e.target.value)} placeholder="당신의 이야기를 들려주세요" rows={5} required aria-describedby="story-guidance reservation-bytes" /><small id="reservation-bytes" className={`byte-counter ${byteLength(text) > STORY_MAX_BYTES ? "error-message" : ""}`}>{byteLength(text)} / {STORY_MAX_BYTES}바이트</small></label><label className="photo-upload">{preview ? <img src={preview} alt="선택한 사진 미리보기" /> : <span className="photo-upload-copy"><strong>＋</strong>사진 추가<small>JPG, PNG, WebP · 한 장 · 최대 5MB</small></span>}<span className="sr-only">사진 추가</span><input aria-label="사진 추가" name="photo" type="file" accept="image/jpeg,image/png,image/webp" required onChange={(e) => { const file = e.target.files?.[0]; if (file) trackActivity("photo_selected"); setPreview(file ? URL.createObjectURL(file) : ""); }} /></label></fieldset>
      <fieldset className="reservation-question"><legend><span>02</span> 성함과 이메일을 남겨주세요</legend><label><span className="sr-only">성함</span><input name="displayName" autoComplete="name" maxLength={40} placeholder="성함" value={isAnonymous ? "익명" : displayName} onChange={(e) => setDisplayName(e.target.value)} disabled={isAnonymous} required={!isAnonymous} /></label><label className="anonymous-option"><input type="checkbox" name="isAnonymous" value="true" checked={isAnonymous} onChange={(e) => setIsAnonymous(e.target.checked)} />익명</label><label><span className="sr-only">이메일</span><input name="email" type="email" autoComplete="email" maxLength={254} placeholder="이메일" required /></label></fieldset>
      <fieldset className="reservation-question"><legend><span>03</span> 결제방법을 선택해주세요</legend><p className="field-description">나중에 이용하고 싶은 방법을 선택해주세요.</p><div className="payment-options">{Object.entries(paymentMethods).map(([value, label]) => <label key={value}><input type="radio" name="paymentMethod" value={value} required /><span>{label}</span></label>)}</div></fieldset>
      <fieldset className="reservation-question"><legend><span>04</span> 결제예정 금액을 선택해주세요</legend><div className="payment-options amount-options">{reservationAmounts.map(amount => <label key={amount}><input name="amount" type="radio" value={amount} required /><span>{amount.toLocaleString("ko-KR")}원</span></label>)}</div></fieldset>
      {error && <p role="alert" className="error-message">{error}</p>}<button className="button primary reservation-submit" onClick={() => trackActivity("reservation_submit_click")} disabled={busy || byteLength(text) > STORY_MAX_BYTES}>{busy ? "예약을 접수하는 중…" : "기부 예약 접수하기"}</button><p className="reservation-footnote">예약한 이야기는 운영진이 확인해요.</p>
    </fieldset></form>
    <dialog ref={reasonDialog} className="reservation-reason-dialog" aria-labelledby="reservation-reason-title" onCancel={event => { if (locked.current) event.preventDefault(); }}>
      <div className="section-heading"><h2 id="reservation-reason-title">왜 기부 예약을 하시게 되었나요?</h2><button type="button" className="text-button" aria-label="예약 이유 질문 닫기" disabled={busy} onClick={() => reasonDialog.current?.close()}>닫기</button></div>
      <form onSubmit={submit} onChange={() => { requestId.current = ""; }}><fieldset disabled={busy}>
        <fieldset className="reservation-question"><legend className="sr-only">예약 이유</legend><div className="reason-options">{Object.entries(reasons).map(([value, label]) => <label key={value}><input type="radio" name="reason" value={value} checked={reason === value} onChange={() => setReason(value)} required />{label}</label>)}</div>{reason === "other" ? <label className="other-reason"><span className="sr-only">기타 이유</span><input name="reasonOther" maxLength={300} placeholder="예약하게 된 이유를 들려주세요" required /></label> : <input type="hidden" name="reasonOther" value="" />}</fieldset>
        {reasonError && <p role="alert" className="error-message">{reasonError}</p>}
        <button type="submit" className="button primary reservation-submit" disabled={busy}>{busy ? "예약을 접수하는 중…" : "예약 접수 완료하기"}</button>
      </fieldset></form>
    </dialog>
  </section>;
}
