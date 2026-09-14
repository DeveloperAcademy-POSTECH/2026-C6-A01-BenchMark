"use client";
import { useEffect, useRef, useState } from "react";

function deviceId() {
  let id = localStorage.getItem("mat-device");
  if (!id || !/^[a-f0-9-]{36}$/i.test(id)) { id = crypto.randomUUID(); localStorage.setItem("mat-device", id); }
  return id;
}
export function Reaction({ id, initialCount }: { id: string; initialCount: number }) {
  const [count, setCount] = useState(initialCount);
  const [reacted, setReacted] = useState(false);
  const [ready, setReady] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const locked = useRef(false);
  useEffect(() => {
    const controller = new AbortController();
    async function load() {
      try {
        const response = await fetch(`/api/stories/${id}/reaction`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ deviceId: deviceId(), action: "status" }), signal: controller.signal });
        const result = await response.json(); if (!response.ok) throw new Error(result.error);
        setCount(result.count); setReacted(result.reacted); setReady(true);
      } catch { if (!controller.signal.aborted) setError("공감 정보를 확인하지 못했어요. 새로고침 후 다시 시도해주세요."); }
    }
    void load(); return () => controller.abort();
  }, [id]);
  async function react() {
    if (locked.current || reacted) return;
    locked.current = true; setBusy(true); setError("");
    try {
      const response = await fetch(`/api/stories/${id}/reaction`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ deviceId: deviceId(), action: "react" }) });
      const result = await response.json(); if (!response.ok) throw new Error(result.error);
      setCount(result.count); setReacted(result.reacted);
    } catch (e) { setError(e instanceof Error ? e.message : "공감을 남기지 못했어요. 다시 시도해주세요."); }
    finally { locked.current = false; setBusy(false); }
  }
  return <div className="reaction-wrap"><button className={`reaction-button ${reacted ? "reacted" : ""}`} disabled={!ready || busy || reacted} onClick={react} aria-pressed={reacted}><span aria-hidden="true">{reacted ? "♥" : "♡"}</span> {busy ? "마음을 전하는 중…" : reacted ? "공감을 전했어요" : "이 이야기에 공감해요"}<strong>{count}</strong></button><p aria-live="polite">{reacted ? "이야기의 주인공에게 따뜻한 마음이 전해졌어요." : "마음이 닿았다면, 공감을 남겨주세요."}</p>{error && <p className="error-message" role="alert">{error}</p>}</div>;
}
