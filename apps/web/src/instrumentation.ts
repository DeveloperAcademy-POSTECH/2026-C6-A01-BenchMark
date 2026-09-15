export async function register() {
  if (process.env.NEXT_RUNTIME !== "nodejs" || process.env.NEXT_PHASE === "phase-production-build") return;
  const { pruneActivity } = await import("./lib/activity-store");
  const runtime = globalThis as typeof globalThis & { activityPruner?: ReturnType<typeof setInterval> };
  if (runtime.activityPruner) return;
  let running = false;
  const prune = async () => {
    if (running) return;
    running = true;
    try { await pruneActivity(); } catch { console.error("Activity retention cleanup failed."); }
    finally { running = false; }
  };
  await prune();
  runtime.activityPruner = setInterval(() => { void prune(); }, 60 * 60 * 1000);
  runtime.activityPruner.unref();
}
