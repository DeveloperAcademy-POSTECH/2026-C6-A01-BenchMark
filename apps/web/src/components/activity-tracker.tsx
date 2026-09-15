"use client";
import { useEffect } from "react";
import { usePathname } from "next/navigation";
import { startActivity } from "@/lib/activity-client";
import { publicPath } from "@/lib/activity";
export function ActivityTracker({ storyId }: { storyId?: string }) {
  const path = usePathname();
  useEffect(() => {
    let stop: (() => void) | undefined;
    // Deferring installation avoids a duplicate visit from React Strict Mode effect replay.
    const timer = setTimeout(() => {
      try { if (publicPath.safeParse(path).success) stop = startActivity(path, storyId); }
      catch { /* Analytics is optional when browser capabilities are unavailable. */ }
    }, 0);
    return () => { clearTimeout(timer); stop?.(); };
  }, [path, storyId]);
  return null;
}
