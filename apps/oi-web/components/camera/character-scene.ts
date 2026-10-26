import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { DRACOLoader } from "three/addons/loaders/DRACOLoader.js";
import type { CharacterId, Placements } from "./composition";

function release(object: THREE.Object3D) {
  const textures = new Set<THREE.Texture>();
  object.traverse(node => {
    if (!(node instanceof THREE.Mesh)) return;
    node.geometry.dispose();
    for (const material of Array.isArray(node.material) ? node.material : [node.material]) {
      for (const value of Object.values(material)) if (value instanceof THREE.Texture) textures.add(value);
      material.dispose();
    }
  });
  for (const texture of textures) { texture.dispose(); const data = texture.source.data; if (typeof ImageBitmap !== "undefined" && data instanceof ImageBitmap) data.close(); }
}
function placeholder(color: number) {
  const group = new THREE.Group();
  const material = new THREE.MeshStandardMaterial({ color, roughness: .65 });
  const body = new THREE.Mesh(new THREE.CapsuleGeometry(.23, .25, 6, 16), material);
  body.position.y = -.12; group.add(body);
  const head = new THREE.Mesh(new THREE.SphereGeometry(.32, 20, 16), material); head.position.y = .28; group.add(head);
  for (const x of [-.11, .11]) {
    const eye = new THREE.Mesh(new THREE.SphereGeometry(.045, 10, 8), new THREE.MeshStandardMaterial({ color: 0xffffff }));
    eye.position.set(x, .31, .3); group.add(eye);
  }
  return group;
}
export function createCharacterScene(onStatus: (id: CharacterId, ready: boolean) => void) {
  const renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true });
  renderer.setPixelRatio(1); renderer.setClearColor(0, 0); renderer.outputColorSpace = THREE.SRGBColorSpace;
  const scene = new THREE.Scene();
  const camera = new THREE.OrthographicCamera(-.5, .5, .5, -.5, .01, 100); camera.position.z = 10;
  scene.add(new THREE.HemisphereLight(0xffffff, 0x897765, 2));
  const light = new THREE.DirectionalLight(0xffffff, 3); light.position.set(-2, 4, 5); scene.add(light);
  const groups = { postech: new THREE.Group(), kaist: new THREE.Group() };
  let disposed = false;
  const draco = new DRACOLoader().setDecoderPath("/draco/");
  const loader = new GLTFLoader().setDRACOLoader(draco);
  for (const id of ["postech", "kaist"] as const) {
    groups[id].add(placeholder(id === "postech" ? 0xca1260 : 0x237ec9)); scene.add(groups[id]);
    loader.load(`/models/${id}.glb`, gltf => {
      if (disposed) { release(gltf.scene); return; }
      const box = new THREE.Box3().setFromObject(gltf.scene), size = box.getSize(new THREE.Vector3());
      if (!Number.isFinite(size.y) || size.y <= 0) { release(gltf.scene); onStatus(id, false); return; }
      const center = box.getCenter(new THREE.Vector3());
      const normalization = new THREE.Group(); gltf.scene.position.sub(center); normalization.add(gltf.scene); normalization.scale.setScalar(1 / size.y);
      release(groups[id]); groups[id].clear(); groups[id].add(normalization); onStatus(id, true);
    }, undefined, () => { if (!disposed) onStatus(id, false); });
  }
  let width = 0, height = 0;
  return {
    render(w: number, h: number, placements: Placements) {
      if (width !== w || height !== h) { width = w; height = h; renderer.setSize(w, h, false); camera.left = -w / h / 2; camera.right = w / h / 2; camera.updateProjectionMatrix(); }
      for (const id of ["postech", "kaist"] as const) {
        const p = placements[id], group = groups[id]; group.visible = p.visible;
        group.position.set((p.x - .5) * w / h, .5 - p.y, 0); group.scale.setScalar(p.scale); group.rotation.y = p.rotation * Math.PI / 180;
      }
      renderer.render(scene, camera); return renderer.domElement;
    },
    dispose() { disposed = true; release(scene); draco.dispose(); renderer.dispose(); renderer.forceContextLoss(); },
  };
}
