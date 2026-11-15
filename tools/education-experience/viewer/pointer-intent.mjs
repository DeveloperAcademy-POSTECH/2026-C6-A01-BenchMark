// A gesture remains a drag/multitouch gesture until every pointer is released.
export class PointerIntent {
  constructor(threshold = 8) { this.threshold = threshold; this.points = new Map(); this.reset(); }
  reset() { this.points.clear(); this.mode = 'idle'; this.multi = false; this.origin = null; this.last = null; this.pinch = 0; }
  distance() { const [a,b] = [...this.points.values()]; return a && b ? Math.hypot(a.x-b.x,a.y-b.y) : 0; }
  begin(id,x,y,button = 0) {
    if (button !== 0 || this.points.has(id)) return false;
    if (!this.points.size) { this.mode = 'pending'; this.multi = false; this.origin = this.last = {x,y}; }
    this.points.set(id,{x,y});
    if (this.points.size > 1) { this.multi = true; this.mode = 'pinch'; this.pinch = this.distance(); }
    return true;
  }
  move(id,x,y) {
    if (!this.points.has(id)) return null;
    this.points.set(id,{x,y});
    if (this.mode === 'pinch' && this.points.size === 2) {
      const distance = this.distance(), ratio = this.pinch > 0 && distance > 0 ? distance / this.pinch : 1;
      this.pinch = distance;
      return {kind:'zoom',ratio};
    }
    if (this.multi) return null;
    if (this.mode === 'pending' && Math.hypot(x-this.origin.x,y-this.origin.y) > this.threshold) this.mode = 'drag';
    if (this.mode !== 'drag') return null;
    const delta = {kind:'rotate',dx:x-this.last.x,dy:y-this.last.y}; this.last = {x,y};
    return delta;
  }
  end(id,x,y,cancelled = false) {
    if (!this.points.has(id)) return false;
    this.move(id,x,y); // A release outside the tolerance also cancels a tap.
    const tap = !cancelled && !this.multi && this.points.size === 1 && this.mode === 'pending';
    this.points.delete(id);
    if (!this.points.size) this.reset();
    else { this.multi = true; this.mode = 'blocked'; }
    return tap;
  }
}

export function installBuildingGestures({canvas,intent,onStart,onRotate,onZoom,onTap,onMode}) {
  const changed = () => onMode?.(intent.mode);
  canvas.addEventListener('pointerdown',e => {
    if (!intent.begin(e.pointerId,e.clientX,e.clientY,e.button)) return;
    onStart(); changed();
    try { canvas.setPointerCapture(e.pointerId); } catch { /* Synthetic/accessibility input need not capture. */ }
  });
  canvas.addEventListener('pointermove',e => {
    const action = intent.move(e.pointerId,e.clientX,e.clientY); changed();
    if (action?.kind === 'rotate') onRotate(action.dx,action.dy);
    if (action?.kind === 'zoom') onZoom(action.ratio);
  });
  for (const type of ['pointerup','pointercancel','lostpointercapture']) canvas.addEventListener(type,e => {
    const tap = intent.end(e.pointerId,e.clientX,e.clientY,type !== 'pointerup'); changed();
    if (tap) onTap(e);
  });
  document.addEventListener('visibilitychange',() => { if (document.hidden) { intent.reset(); changed(); } });
  window.addEventListener('blur',() => { intent.reset(); changed(); });
}
