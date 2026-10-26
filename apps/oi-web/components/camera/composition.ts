export type CharacterId = "postech" | "kaist";
export type Placement = { x: number; y: number; scale: number; rotation: number; visible: boolean };
export type Placements = Record<CharacterId, Placement>;
export const defaults = (): Placements => ({
  postech: { x: .3, y: .58, scale: .35, rotation: 0, visible: true },
  kaist: { x: .7, y: .58, scale: .35, rotation: 0, visible: false },
});
export const clamp = (value: number, min: number, max: number) => Math.max(min, Math.min(max, value));
export function coverCrop(sw: number, sh: number, dw: number, dh: number) {
  const scale = Math.max(dw / sw, dh / sh);
  const width = dw / scale, height = dh / scale;
  return { x: (sw - width) / 2, y: (sh - height) / 2, width, height };
}
export function drawCamera(ctx: CanvasRenderingContext2D, source: CanvasImageSource, sw: number, sh: number, w: number, h: number, mirror: boolean) {
  const crop = coverCrop(sw, sh, w, h);
  ctx.save();
  if (mirror) { ctx.translate(w, 0); ctx.scale(-1, 1); }
  ctx.drawImage(source, crop.x, crop.y, crop.width, crop.height, 0, 0, w, h);
  ctx.restore();
}
