import { FilesetResolver, ImageSegmenter } from "@mediapipe/tasks-vision";
let segmenter: ImageSegmenter | undefined;
self.onmessage = async (event: MessageEvent<{ type: string; frame?: ImageBitmap }>) => {
  const frame = event.data.frame;
  try {
    if (event.data.type === "init") {
      segmenter = await ImageSegmenter.createFromOptions(await FilesetResolver.forVisionTasks("/mediapipe/wasm"), {
        baseOptions: { modelAssetPath: "/mediapipe/selfie_segmenter.tflite", delegate: "CPU" },
        runningMode: "IMAGE", outputConfidenceMasks: true, outputCategoryMask: false,
      });
      self.postMessage({ type: "ready" });
    } else if (frame && segmenter) {
      segmenter.segment(frame, result => {
        const mask = result.confidenceMasks?.[0];
        if (!mask) throw new Error("No mask");
        const values = new Float32Array(mask.getAsFloat32Array());
        self.postMessage({ type: "mask", frame, values, width: mask.width, height: mask.height }, { transfer: [frame, values.buffer] });
      });
    } else { frame?.close(); }
  } catch { frame?.close(); self.postMessage({ type: "error" }); }
};
