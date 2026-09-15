import { activityEvent, type ActivityEvent } from "./activity";

type Action = { name: ActivityEvent["name"]; properties: Record<string, string | number> };
export function trackActivity(name: Action["name"], properties: Action["properties"] = {}) {
  try { window.dispatchEvent(new CustomEvent("mat-activity", { detail: { name, properties } })); } catch { /* Analytics must never interrupt the page. */ }
}
const sessionKey = "mat-activity-session";
let session: { id: string; last: number } | undefined;
const idleLimit = 30 * 60 * 1000;
function currentSession(now: number) {
  if (!session) {
    try {
      const navigation = performance.getEntriesByType("navigation")[0] as PerformanceNavigationTiming | undefined;
      const saved = navigation?.type === "reload" ? JSON.parse(sessionStorage.getItem(sessionKey) || "null") : null;
      if (saved && /^[0-9a-f-]{36}$/.test(saved.id) && typeof saved.last === "number" && now >= saved.last && now - saved.last < idleLimit) session = saved;
    } catch { /* Memory-only sessions work when storage is unavailable. */ }
  }
  if (!session || now - session.last >= idleLimit) session = { id: crypto.randomUUID(), last: now };
  session.last = now;
  try { sessionStorage.setItem(sessionKey, JSON.stringify(session)); } catch { /* No persistent storage is required. */ }
  return session.id;
}

export function startActivity(path: string, storyId?: string) {
  let visitId = crypto.randomUUID();
  let sessionId = currentSession(Date.now());
  const reached = new Set<number>();
  let queue: { event: ActivityEvent; attempts: number }[] = [];
  let sending = false;
  let stopped = false;
  let activeSince: number | undefined = document.visibilityState === "visible" && document.hasFocus() ? performance.now() : undefined;
  let lastInteraction = Date.now();
  let activeMs = 0;
  function record(name: Action["name"], properties: Action["properties"] = {}) {
    try {
      const nextSession = session?.id ?? sessionId;
      if (nextSession !== sessionId) {
        sessionId = nextSession; visitId = crypto.randomUUID(); reached.clear();
        record("page_view");
      }
      const parsed = activityEvent.safeParse({ id: crypto.randomUUID(), visitId, sessionId, occurredAt: new Date().toISOString(), path, ...(storyId ? { storyId } : {}), name, properties });
      if (parsed.success && queue.length < 100) queue.push({ event: parsed.data, attempts: 0 });
    } catch { /* Browser capability failures must not affect the primary interaction. */ }
  }
  async function flush() {
    if (sending || !queue.length) return;
    sending = true;
    const batch = queue.filter(item => item.event.sessionId === queue[0].event.sessionId).slice(0, 20);
    batch.forEach(item => { item.attempts++; });
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 4000);
    let discard = false;
    try {
      const response = await fetch("/api/activity", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ events: batch.map(item => item.event) }), keepalive: true, signal: controller.signal });
      discard = response.ok || (response.status >= 400 && response.status < 500 && response.status !== 429);
    } catch { /* Retry the same event IDs within the bounded in-memory queue. */ }
    finally {
      clearTimeout(timeout);
      queue = queue.filter(item => !batch.includes(item) || (!discard && item.attempts < 3));
      sending = false;
      if (stopped && queue.length) setTimeout(() => { void flush(); }, 1000);
    }
  }
  function accrue() {
    const now = performance.now();
    if (activeSince !== undefined) activeMs += Math.max(0, Math.min(now - activeSince, 15000));
    activeSince = document.visibilityState === "visible" && document.hasFocus() ? now : undefined;
  }
  function time() {
    accrue();
    if (activeMs >= 1) { record("active_time", { milliseconds: Math.min(60000, Math.floor(activeMs)) }); activeMs = 0; }
  }
  function scroll() {
    if (document.visibilityState !== "visible") return;
    const height = document.documentElement.scrollHeight;
    const percent = Math.min(100, Math.floor((window.scrollY + window.innerHeight) / height * 100));
    for (const threshold of [25, 50, 75, 100]) if (percent >= threshold && !reached.has(threshold)) {
      reached.add(threshold); record("scroll_depth", { percent: threshold });
    }
  }
  function interaction() {
    if (Date.now() - lastInteraction < 1000) return;
    // Heartbeats do not extend the inactivity timeout.
    if (Date.now() - lastInteraction >= idleLimit) {
      session = undefined;
      try { sessionStorage.removeItem(sessionKey); } catch { /* Optional storage. */ }
    }
    lastInteraction = Date.now();
    currentSession(lastInteraction);
  }
  function userScroll() { interaction(); scroll(); }
  function action(event: Event) {
    interaction();
    const detail = (event as CustomEvent<Action>).detail;
    if (detail) record(detail.name, detail.properties);
  }
  function click(event: MouseEvent) {
    interaction();
    const link = event.target instanceof Element ? event.target.closest("a[href]") : null;
    if (!(link instanceof HTMLAnchorElement)) return;
    const url = new URL(link.href);
    if (url.origin !== location.origin) return;
    const match = /^\/stories\/([0-9a-f-]{36})$/.exec(url.pathname);
    const target = match ? "story" : ({ "/": "home", "/stories": "stories", "/reserve": "reserve" } as Record<string, string>)[url.pathname];
    if (target) record("link_click", { target, ...(match ? { targetStoryId: match[1] } : {}) });
  }
  function visibility() { time(); if (document.visibilityState !== "visible") void flush(); }
  function focus() { interaction(); accrue(); }
  function blur() { time(); void flush(); }
  function pageHide() { time(); void flush(); }
  function pageShow(event: PageTransitionEvent) {
    if (event.persisted) { visitId = crypto.randomUUID(); reached.clear(); record("page_view"); accrue(); scroll(); }
  }
  record("page_view"); scroll();
  const heartbeat = setInterval(() => { time(); void flush(); }, 15000);
  const transport = setInterval(() => { void flush(); }, 5000);
  window.addEventListener("mat-activity", action);
  window.addEventListener("scroll", userScroll, { passive: true });
  window.addEventListener("pointerdown", interaction, { passive: true });
  window.addEventListener("keydown", interaction);
  window.addEventListener("click", click);
  window.addEventListener("focus", focus); window.addEventListener("blur", blur);
  window.addEventListener("pagehide", pageHide); window.addEventListener("pageshow", pageShow);
  document.addEventListener("visibilitychange", visibility);
  return () => {
    time(); stopped = true; void flush();
    clearInterval(heartbeat); clearInterval(transport);
    window.removeEventListener("mat-activity", action); window.removeEventListener("scroll", userScroll);
    window.removeEventListener("pointerdown", interaction); window.removeEventListener("keydown", interaction); window.removeEventListener("click", click);
    window.removeEventListener("focus", focus); window.removeEventListener("blur", blur);
    window.removeEventListener("pagehide", pageHide); window.removeEventListener("pageshow", pageShow);
    document.removeEventListener("visibilitychange", visibility);
  };
}
