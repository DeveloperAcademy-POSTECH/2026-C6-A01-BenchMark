import { test } from "node:test";
import assert from "node:assert/strict";
import { coverCrop, drawCamera } from "../src/components/camera/composition";
test("landscape camera is center cropped to portrait without stretching", () => {
  assert.deepEqual(coverCrop(1280, 720, 720, 960), { x: 370, y: 0, width: 540, height: 720 });
});
test("front camera mirror is scoped to the camera layer", () => {
  const calls: string[] = [];
  const ctx = { save: () => calls.push("save"), translate: () => calls.push("translate"), scale: () => calls.push("mirror"), drawImage: () => calls.push("draw"), restore: () => calls.push("restore") } as unknown as CanvasRenderingContext2D;
  drawCamera(ctx, {} as CanvasImageSource, 1280, 720, 720, 960, true);
  assert.deepEqual(calls, ["save", "translate", "mirror", "draw", "restore"]);
});
