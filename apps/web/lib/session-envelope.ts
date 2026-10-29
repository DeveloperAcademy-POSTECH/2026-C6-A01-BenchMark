import { createDecipheriv, createHash } from "node:crypto";

let cached: { envelope:string; wrappingKey:string; value:string } | undefined;
export function sealedSessionSecret(envelope: string | undefined, wrappingKey: string | undefined) {
  if (!envelope || !wrappingKey) return undefined;
  if (cached?.envelope === envelope && cached.wrappingKey === wrappingKey) return cached.value;
  const box: {version:number;iv:string;tag:string;ciphertext:string} = JSON.parse(envelope);
  if (box.version !== 1) throw new Error("Unsupported session envelope");
  const key = createHash("sha256").update("benchmark-session-wrap-v1\0").update(wrappingKey).digest();
  const decipher = createDecipheriv("aes-256-gcm",key,Buffer.from(box.iv,"base64"));
  decipher.setAAD(Buffer.from("benchmark-session-secret-v1"));
  decipher.setAuthTag(Buffer.from(box.tag,"base64"));
  const value = Buffer.concat([decipher.update(Buffer.from(box.ciphertext,"base64")),decipher.final()]).toString();
  if (value.length < 32) throw new Error("Invalid session envelope");
  cached = {envelope,wrappingKey,value};
  return value;
}
