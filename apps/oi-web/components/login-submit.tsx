"use client";
import { useFormStatus } from "react-dom";
export function LoginSubmit() {
  const { pending } = useFormStatus();
  return <button className="button primary" disabled={pending}>{pending ? "Google로 연결하는 중…" : "Google 계정으로 계속하기"}</button>;
}
