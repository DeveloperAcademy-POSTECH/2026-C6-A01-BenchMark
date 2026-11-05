import { AsyncLocalStorage } from "node:async_hooks";
import { randomUUID } from "node:crypto";

const storage = new AsyncLocalStorage<Cloudflare.Env>();
export function runWithStorageBindings<T>(env: Cloudflare.Env, action: () => T) {
  return storage.run(env, action);
}

export function bindings() {
  const env = storage.getStore();
  if (!env?.DB || !env.BUCKET) throw new Error("Sites storage is not configured");
  return { db: env.DB, bucket: env.BUCKET };
}

export async function storePhoto(photo: Uint8Array) {
  const key = `photos/${randomUUID()}.jpg`;
  await bindings().bucket.put(key, photo, { httpMetadata: { contentType: "image/jpeg" } });
  return key;
}

export async function loadPhoto(key: string) {
  const object = await bindings().bucket.get(key);
  if (!object) throw new Error("Stored photo is missing");
  return Buffer.from(await object.arrayBuffer());
}
