"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";

export function AdminLogin() {
  const router = useRouter(); const [busy, setBusy] = useState(false); const [error, setError] = useState("");
  async function login(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError("");
    const form = new FormData(event.currentTarget);
    try {
      const response = await fetch("/api/admin/session", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ password: form.get("password") }) });
      const result = await response.json(); if (!response.ok) throw new Error(result.error);
      router.refresh();
    } catch (e) { setError(e instanceof Error ? e.message : "로그인하지 못했습니다."); }
    finally { setBusy(false); }
  }
  return <section className="login-panel"><span className="eyebrow">쉼, 펴 운영팀</span><h1>관리자 페이지</h1><p>팀에서 공유받은 비밀번호를 입력해주세요.</p><form onSubmit={login}><label htmlFor="password">비밀번호</label><input id="password" name="password" type="password" autoComplete="current-password" required maxLength={256} /><button className="button primary" disabled={busy}>{busy ? "확인 중…" : "관리자 페이지로 이동"}</button>{error && <p className="error-message" role="alert">{error}</p>}</form></section>;
}
