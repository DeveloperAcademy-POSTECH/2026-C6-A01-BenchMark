"use client";
/* eslint-disable @next/next/no-img-element */
import { activityReporter } from "@/lib/activity-client";
import { useEffect, useRef, useState } from "react";
import { reactionKinds, reactionLabels, emptyCounts, type ReactionKind } from "@/lib/story";

function deviceId() {
  let id = localStorage.getItem("mat-device");
  if (!id || !/^[a-f0-9-]{36}$/i.test(id)) { id = crypto.randomUUID(); localStorage.setItem("mat-device", id); }
  return id;
}
export function Reaction({ id }: { id?: string }) {
  const [counts, setCounts] = useState(emptyCounts);
  const [selected, setSelected] = useState<ReactionKind[]>([]);
  const [ready, setReady] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const locked = useRef(false);
  useEffect(() => {
    if (!id) return;
    const controller = new AbortController();
    async function load() {
      try {
        const response = await fetch(`/api/stories/${id}/reaction`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ deviceId: deviceId(), action: "status" }), signal: controller.signal });
        const result = await response.json(); if (!response.ok) throw new Error(result.error);
        setCounts(result.counts); setSelected(result.selected); setReady(true);
      } catch { if (!controller.signal.aborted) setError("반응 정보를 확인하지 못했어요. 새로고침 후 다시 시도해주세요."); }
    }
    void load(); return () => controller.abort();
  }, [id]);
  async function react(kind: ReactionKind) {
    const reportActivity = activityReporter();
    if (!id || !ready || locked.current) return;
    const action = selected.includes(kind) ? "remove" : "react";
    reportActivity("reaction_attempt", { kind, action });
    locked.current = true; setBusy(true); setError("");
    try {
      const response = await fetch(`/api/stories/${id}/reaction`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ deviceId: deviceId(), action, kind }) });
      const result = await response.json(); if (!response.ok) throw new Error(result.error);
      setCounts(result.counts); setSelected(result.selected);
      reportActivity("reaction_success", { kind, action });
    } catch (e) {
      reportActivity("reaction_failure", { kind, action });
      try {
        const response = await fetch(`/api/stories/${id}/reaction`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ deviceId: deviceId(), action: "status" }) });
        const result = await response.json(); if (!response.ok) throw new Error(result.error);
        setCounts(result.counts); setSelected(result.selected);
        setError(e instanceof Error ? e.message : "반응을 처리하지 못했어요. 현재 상태를 확인한 뒤 다시 시도해주세요.");
      } catch {
        setReady(false);
        setError("반응 상태를 확인하지 못했어요. 새로고침 후 다시 시도해주세요.");
      }
    }
    finally { locked.current = false; setBusy(false); }
  }
  return <section className="reaction-wrap" aria-label="이야기에 마음 남기기"><div className="reaction-grid">{reactionKinds.map((kind) => <button key={kind} className={`reaction-button ${selected.includes(kind) ? "reacted" : ""}`} disabled={!ready || busy} onClick={() => react(kind)} aria-pressed={selected.includes(kind)} aria-label={`${reactionLabels[kind]} ${counts[kind]}개`}><img src={`/brand/reaction-${kind}.png`} width="28" height="28" alt="" /><span>{reactionLabels[kind]}</span><strong>{counts[kind]}</strong></button>)}</div><p>{id ? "마음이 닿는 반응을 모두 남겨주세요." : "이야기가 공개되면 마음을 남길 수 있어요."}</p>{error && <p className="error-message" role="alert">{error}</p>}</section>;
}
