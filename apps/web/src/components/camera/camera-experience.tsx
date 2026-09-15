"use client";
/* eslint-disable @next/next/no-img-element */
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { clamp, defaults, drawCamera, type CharacterId } from "./composition";
import styles from "./camera.module.css";

export function CameraExperience() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [running, setRunning] = useState(false), [ready, setReady] = useState(false);
  const [front, setFront] = useState(false), [behind, setBehind] = useState(false);
  const [placements, setPlacements] = useState(defaults);
  const [selected, setSelected] = useState<CharacterId>("postech");
  const [message, setMessage] = useState("");
  const [modelStatus, setModelStatus] = useState({ postech: false, kaist: false });
  const [photo, setPhoto] = useState<{ url: string; blob: Blob } | null>(null);
  const [capturing, setCapturing] = useState(false);
  const settings = useRef({ placements, behind });
  useEffect(() => { settings.current = { placements, behind }; }, [placements, behind]);
  useEffect(() => () => { if (photo) URL.revokeObjectURL(photo.url); }, [photo]);
  const points = useRef(new Map<number, { x: number; y: number }>());
  const captureLock = useRef(false), generation = useRef(0);

  useEffect(() => {
    if (!running) return;
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const session = generation;
    const activePoints = points.current;
    const video = document.createElement("video"); video.autoplay = true; video.muted = true; video.playsInline = true;
    const source = document.createElement("canvas"), maskCanvas = document.createElement("canvas"), person = document.createElement("canvas");
    let stream: MediaStream | undefined, scene: ReturnType<typeof import("./character-scene").createCharacterScene> | undefined;
    let worker: Worker | undefined, workerReady = false, pending = false, disposed = false, failed = false;
    let raf = 0, lastFrame = 0, lastVideoTime = -1;
    let segmentedFrame: ImageBitmap | undefined;
    let segmentationStarted = 0;
    const onVisibility = () => {
      if (document.hidden && !disposed) { setRunning(false); setReady(false); setMessage("카메라를 일시 중지했어요. 다시 시작해주세요."); }
    };
    document.addEventListener("visibilitychange", onVisibility);
    const stopStream = () => { stream?.getTracks().forEach(track => track.stop()); video.srcObject = null; };
    function fail(text: string) { if (!disposed) { setMessage(text); setReady(false); setRunning(false); } }
    function disableSegmentation() {
      failed = true; worker?.terminate(); worker = undefined; pending = false;
      segmentedFrame?.close(); segmentedFrame = undefined;
      setBehind(false); setMessage("인물 가림을 사용할 수 없어 일반 합성으로 전환했어요. 최신 Safari 또는 Chrome에서 다시 시도해주세요.");
    }
    async function start() {
      try {
        if (!navigator.mediaDevices?.getUserMedia) throw new Error("unsupported");
        stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: front ? "user" : "environment" }, width: { ideal: 1280 }, height: { ideal: 960 } }, audio: false });
        if (disposed) { stopStream(); return; }
        video.srcObject = stream; await video.play();
        const { createCharacterScene } = await import("./character-scene");
        if (disposed) return;
        scene = createCharacterScene((id, loaded) => { if (!disposed) setModelStatus(s => ({ ...s, [id]: loaded })); });
        stream.getVideoTracks()[0]?.addEventListener("ended", () => { if (!disposed) fail("카메라 연결이 종료되었어요. 다시 시작해주세요."); });
        setReady(true);
        function render(now: number) {
          if (disposed) return;
          raf = requestAnimationFrame(render);
          if (!video.videoWidth || !scene) return;
          const w = 720, h = 960;
          if (canvas!.width !== w) { canvas!.width = w; canvas!.height = h; source.width = w; source.height = h; person.width = w; person.height = h; }
          const sourceContext = source.getContext("2d")!;
          drawCamera(sourceContext, video, video.videoWidth, video.videoHeight, w, h, front);
          const wantsBehind = settings.current.behind;
          if (wantsBehind && !worker && !failed) {
            try {
              segmentationStarted = now;
              worker = new Worker(new URL("./person-segmentation.worker.ts", import.meta.url));
              worker.onerror = () => { if (!disposed) disableSegmentation(); };
              worker.onmessage = event => {
                if (disposed) { event.data.frame?.close(); return; }
                if (event.data.type === "ready") { workerReady = true; setMessage("인물 가림이 준비됐어요. 사람 옆에 캐릭터를 배치해보세요."); }
                if (event.data.type === "error") { disableSegmentation(); return; }
                if (event.data.type === "mask") {
                  pending = false; segmentedFrame?.close(); segmentedFrame = event.data.frame;
                  maskCanvas.width = event.data.width; maskCanvas.height = event.data.height;
                  const maskContext = maskCanvas.getContext("2d")!, data = maskContext.createImageData(maskCanvas.width, maskCanvas.height);
                  const values: Float32Array = event.data.values;
                  for (let i = 0; i < values.length; i++) { data.data[i * 4] = 255; data.data[i * 4 + 1] = 255; data.data[i * 4 + 2] = 255; data.data[i * 4 + 3] = Math.round(clamp((values[i] - .3) / .4, 0, 1) * 255); }
                  maskContext.putImageData(data, 0, 0);
                }
              };
              worker.postMessage({ type: "init" }); setMessage("인물 가림을 준비하고 있어요…");
            } catch { disableSegmentation(); }
          }
          if (wantsBehind && worker && ((!workerReady && now - segmentationStarted > 30000) || (pending && now - lastFrame > 10000))) disableSegmentation();
          if (wantsBehind && workerReady && worker && !pending && now - lastFrame > 100 && video.currentTime !== lastVideoTime) {
            pending = true; lastFrame = now; lastVideoTime = video.currentTime;
            createImageBitmap(source).then(frame => {
              if (disposed || !worker) { frame.close(); return; }
              worker.postMessage({ type: "frame", frame }, [frame]);
            }).catch(() => { if (!disposed) disableSegmentation(); });
          }
          const frame = wantsBehind && segmentedFrame ? segmentedFrame : source;
          ctx!.drawImage(frame, 0, 0, w, h);
          ctx!.drawImage(scene.render(w, h, settings.current.placements), 0, 0);
          if (wantsBehind && segmentedFrame) {
            const pc = person.getContext("2d")!; pc.clearRect(0, 0, w, h); pc.drawImage(segmentedFrame, 0, 0, w, h);
            pc.globalCompositeOperation = "destination-in"; pc.drawImage(maskCanvas, 0, 0, w, h); pc.globalCompositeOperation = "source-over";
            ctx!.drawImage(person, 0, 0);
          }
        }
        raf = requestAnimationFrame(render);
      } catch (error) {
        const name = error instanceof Error ? error.name : "";
        fail(name === "NotAllowedError" ? "카메라 권한을 허용해주세요. 앱 안에서 열었다면 Safari 또는 Chrome으로 열어주세요." : name === "NotFoundError" ? "사용할 카메라를 찾지 못했어요." : "카메라 또는 3D 화면을 시작하지 못했어요. HTTPS 주소에서 최신 Safari 또는 Chrome으로 다시 시도해주세요.");
      }
    }
    void start();
    return () => { disposed = true; document.removeEventListener("visibilitychange", onVisibility); session.current++; cancelAnimationFrame(raf); worker?.terminate(); segmentedFrame?.close(); scene?.dispose(); stopStream(); activePoints.clear(); };
  }, [running, front]);

  function update(values: Partial<(typeof placements)[CharacterId]>) { setPlacements(previous => ({ ...previous, [selected]: { ...previous[selected], ...values } })); }
  function move(event: React.PointerEvent<HTMLCanvasElement>) {
    const old = points.current.get(event.pointerId); if (!old) return;
    const next = { x: event.clientX, y: event.clientY }, rect = event.currentTarget.getBoundingClientRect();
    const other = [...points.current.entries()].find(([id]) => id !== event.pointerId)?.[1];
    points.current.set(event.pointerId, next);
    setPlacements(previous => {
      const p = previous[selected];
      if (other) { const before = Math.hypot(old.x - other.x, old.y - other.y), after = Math.hypot(next.x - other.x, next.y - other.y); return { ...previous, [selected]: { ...p, scale: clamp(p.scale * after / Math.max(before, 1), .1, .85) } }; }
      return { ...previous, [selected]: { ...p, x: clamp(p.x + (next.x - old.x) / rect.width, 0, 1), y: clamp(p.y + (next.y - old.y) / rect.height, 0, 1) } };
    });
  }
  async function capture() {
    if (!ready || !canvasRef.current || captureLock.current) return;
    captureLock.current = true; setCapturing(true); const token = generation.current;
    try {
      const blob = await new Promise<Blob>((resolve, reject) => canvasRef.current!.toBlob(b => b ? resolve(b) : reject(new Error()), "image/jpeg", .92));
      if (token !== generation.current) return;
      setPhoto({ blob, url: URL.createObjectURL(blob) }); setRunning(false); setReady(false);
    } catch { setMessage("사진을 만들지 못했어요. 다시 촬영해주세요."); }
    finally { captureLock.current = false; setCapturing(false); }
  }
  async function share() {
    if (!photo) return;
    const file = new File([photo.blob], "benchmark-photo.jpg", { type: "image/jpeg" });
    if (!navigator.canShare?.({ files: [file] })) { setMessage("아래 사진 다운로드를 이용하거나 사진을 길게 눌러 저장해주세요."); return; }
    try { await navigator.share({ files: [file], title: "쉼, 펴 · 포카전의 추억" }); }
    catch (error) { if (!(error instanceof Error && error.name === "AbortError")) setMessage("공유하지 못했어요. 사진 다운로드를 이용해주세요."); }
  }
  const current = placements[selected];
  return <section className={styles.page}>
    <Link href="/about" className="back-link">← 프로젝트 소개</Link>
    <span className="eyebrow">POSTECH × KAIST · 포카전</span><h1>오늘의 쉼을, 한 컷에.</h1>
    <p>캐릭터를 움직여 친구들과 함께 사진을 남겨보세요.</p>
    <div className={styles.stage}>
      {photo ? <img src={photo.url} alt="캐릭터와 함께 촬영한 사진" /> : <canvas ref={canvasRef} aria-label="캐릭터 합성 카메라. 아래 버튼과 슬라이더로도 위치를 조절할 수 있습니다." onPointerDown={e => { if (!ready || points.current.size >= 2) return; e.currentTarget.setPointerCapture(e.pointerId); points.current.set(e.pointerId, { x: e.clientX, y: e.clientY }); }} onPointerMove={move} onPointerUp={e => points.current.delete(e.pointerId)} onPointerCancel={e => points.current.delete(e.pointerId)} onLostPointerCapture={e => points.current.delete(e.pointerId)} />}
      {!running && !photo && <div className={styles.welcome}><strong>포카전의 추억을 함께 남겨요</strong><p>카메라 접근을 허용하면 시작할 수 있어요.</p><button className="button primary" onClick={() => { setMessage(""); setReady(false); setRunning(true); }}>카메라 시작</button></div>}
      {running && !ready && <div className={styles.welcome} role="status">카메라를 준비하고 있어요…</div>}
    </div>
    <p className={styles.notice}>사진은 서버에 업로드하지 않아요. 공간 고정 없이 화면 위에 합성합니다.</p>
    <p role="status" aria-live="polite">{message}</p>
    {photo ? <div className={styles.actions}><button className="button primary" onClick={share}>사진 공유·저장</button><a className="button secondary" href={photo.url} download="benchmark-photo.jpg">사진 다운로드</a><button className="button secondary" onClick={() => { setPhoto(null); setMessage(""); setRunning(true); }}>다시 촬영</button></div> : <>
      <div className={styles.tabs} aria-label="조절할 캐릭터 선택">{(["postech", "kaist"] as const).map(id => <button key={id} aria-pressed={selected === id} onClick={() => { setSelected(id); setPlacements(p => ({ ...p, [id]: { ...p[id], visible: true } })); }}>{id === "postech" ? "포스텍" : "카이스트"}</button>)}<button onClick={() => setPlacements(p => ({ postech: { ...p.postech, visible: true }, kaist: { ...p.kaist, visible: true } }))}>둘 다 표시</button></div>
      <p className={styles.notice}>{!modelStatus[selected] ? "현재 선택한 캐릭터는 테스트용 임시 3D 모델입니다. 공식 캐릭터 GLB를 준비해주세요." : "캐릭터 모델을 불러왔어요."}</p>
      <div className={styles.controls}>
        <label><input type="checkbox" checked={current.visible} onChange={e => update({ visible: e.target.checked })} /> 선택한 캐릭터 표시</label>
        <label>크기<input type="range" min="0.1" max="0.85" step="0.01" value={current.scale} onChange={e => update({ scale: Number(e.target.value) })} /></label>
        <label>방향 {Math.round(current.rotation)}°<input type="range" min="-180" max="180" value={current.rotation} onChange={e => update({ rotation: Number(e.target.value) })} /></label>
        <details><summary>위치를 슬라이더로 조절</summary><label>좌우<input type="range" min="0" max="1" step="0.01" value={current.x} onChange={e => update({ x: Number(e.target.value) })} /></label><label>상하<input type="range" min="0" max="1" step="0.01" value={current.y} onChange={e => update({ y: Number(e.target.value) })} /></label></details>
        <label><input type="checkbox" checked={behind} onChange={e => setBehind(e.target.checked)} /> 캐릭터를 사람 뒤에 배치</label><small>인물 가림은 실험 기능입니다. 머리카락·손 경계가 흔들리거나 화면이 느려질 수 있어요.</small>
      </div>
      <p className={styles.notice}>한 손가락으로 이동 · 두 손가락으로 크기 조절 · 슬라이더로 회전</p>
      <div className={styles.actions}><button className="button secondary" disabled={!ready || capturing} onClick={() => { setReady(false); setFront(!front); }}>카메라 전환</button><button className="button primary" disabled={!ready || capturing} onClick={capture}>{capturing ? "사진 만드는 중…" : "사진 촬영"}</button><button className="button secondary" onClick={() => setPlacements(defaults())}>초기화</button>{running && <button className="text-button" onClick={() => { setReady(false); setRunning(false); }}>카메라 끄기</button>}</div>
    </>}
  </section>;
}
