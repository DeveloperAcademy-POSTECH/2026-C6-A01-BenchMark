"use client";

import { useRef, useState } from "react";
import { formVersion, registrationFields, registrationSchema, fieldErrors, type FieldErrors } from "@/lib/registration";

export function RegistrationForm({ testMode, retentionDays, contact }: { testMode: boolean; retentionDays: number; contact: string }) {
  const [errors, setErrors] = useState<FieldErrors>({});
  const [message, setMessage] = useState("");
  const [pending, setPending] = useState(false);
  const [complete, setComplete] = useState(false);
  const inFlight = useRef(false);
  const formRef = useRef<HTMLFormElement>(null);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (inFlight.current) return;
    const data = new FormData(event.currentTarget);
    const values = Object.fromEntries(registrationFields.map(({ key }) => [key, data.get(key)]));
    const result = registrationSchema.safeParse({ ...values, consent: data.get("consent") === "on", formVersion });
    setMessage("");
    if (!result.success) {
      const nextErrors = fieldErrors(result.error);
      setErrors(nextErrors);
      const firstField = Object.keys(nextErrors)[0];
      (formRef.current?.elements.namedItem(firstField) as HTMLElement | null)?.focus();
      return;
    }
    setErrors({});
    inFlight.current = true;
    setPending(true);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    try {
      const response = await fetch("/api/registrations", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify(result.data), signal: controller.signal,
      });
      const body = await response.json();
      if (!response.ok) {
        setErrors(body.errors ?? {});
        setMessage(body.errors?.formVersion ?? body.message ?? "접수하지 못했어요. 잠시 후 다시 시도해주세요.");
        return;
      }
      setComplete(true);
    } catch {
      setMessage("접수 결과를 확인하지 못했어요. 연결을 확인한 뒤 다시 시도해주세요. 같은 번호로 재시도해도 중복 저장되지 않아요.");
    } finally {
      clearTimeout(timeout);
      inFlight.current = false;
      setPending(false);
    }
  }

  return <div className="form-card">
    {complete ? <div className="success-state" role="status" aria-live="polite">
      <span className="success-icon" aria-hidden="true">✓</span>
      <p className="eyebrow">THANK YOU</p>
      <h3>{testMode ? "테스트 신청이 접수됐어요" : "함께할 마음을 남겨주셨어요"}</h3>
      <p>{testMode ? "입력한 테스트 정보가 저장됐어요. 실제 기부나 연락은 진행되지 않아요." : "사전신청이 접수됐어요. 같은 번호로 이미 신청했다면 기존 접수가 유지돼요."}</p>
      <p className="small muted">사전신청은 기부금 결제나 벤치 설치 확약이 아닙니다.</p>
      <a className="text-link" href="#about">BenchMark 이야기 다시 보기 <span aria-hidden="true">↗</span></a>
    </div> : <>
      <div className="form-heading"><span className="pill">{testMode ? "테스트 접수" : "사전신청"}</span><span className="small muted">약 30초면 충분해요</span></div>
      <h3>첫 번째 소식을 함께해요.</h3>
      <p className="form-description">{testMode ? "현재 신청 기능을 테스트하고 있어요. 실제 개인정보 대신 테스트 이름과 번호를 입력해주세요." : "이름과 연락처를 남겨주시면 기부 참여 안내를 준비할게요."}</p>
      <form ref={formRef} onSubmit={submit} noValidate aria-busy={pending}>
        <fieldset disabled={pending}>
          <legend className="sr-only">사전신청 정보</legend>
          {registrationFields.map((field) => <div className="field" key={field.key}>
            <label htmlFor={field.key}>{field.label} <span aria-hidden="true">*</span></label>
            <input id={field.key} name={field.key} type={field.type} autoComplete={testMode ? "off" : field.autoComplete}
              maxLength={field.maxLength} placeholder={testMode && field.key === "name" ? "테스트 이름" : field.placeholder}
              required aria-invalid={Boolean(errors[field.key])}
              aria-describedby={`${field.key}-hint${errors[field.key] ? ` ${field.key}-error` : ""}`} />
            <p className="field-hint" id={`${field.key}-hint`}>{field.key === "phone" ? (testMode ? "테스트 번호: 010-0000-숫자 4자리" : "010으로 시작하는 휴대폰 번호를 입력해주세요.") : "최대 50자까지 입력할 수 있어요."}</p>
            {errors[field.key] && <p className="field-error" id={`${field.key}-error`}>{errors[field.key]}</p>}
          </div>)}
          <details className="privacy"><summary>개인정보 수집·이용 안내</summary>
            <dl><dt>수집 항목</dt><dd>이름, 휴대폰 번호</dd><dt>이용 목적</dt><dd>{testMode ? "사전신청 기능 테스트" : "기부 사전신청 접수 및 참여 안내"}</dd><dt>보유 기간</dt><dd>접수일로부터 {retentionDays}일</dd><dt>수집 주체</dt><dd>BenchMark 팀</dd></dl>
            {contact && <p>철회·삭제 문의: <a href={`mailto:${contact}`}>{contact}</a></p>}
            <p>동의를 거부할 수 있으며, 거부 시 사전신청은 이용할 수 없습니다. 서비스 소개는 동의 없이 볼 수 있습니다.</p>
          </details>
          <label className="consent" htmlFor="consent"><input type="checkbox" id="consent" name="consent" required aria-invalid={Boolean(errors.consent)} aria-describedby={errors.consent ? "consent-error" : undefined} /><span>[필수] 개인정보 수집·이용에 동의합니다.</span></label>
          {errors.consent && <p id="consent-error" className="field-error">{errors.consent}</p>}
          {message && <p className="form-error" role="alert">{message}</p>}
          <button className="button submit-button" type="submit">{pending ? "접수하고 있어요…" : testMode ? "테스트 사전신청하기" : "기부 사전신청하기"}<span aria-hidden="true">↗</span></button>
        </fieldset>
        <p className="form-note">지금은 마음만 남겨주세요. 결제는 진행되지 않아요.</p>
      </form>
    </>}
  </div>;
}
