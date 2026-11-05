import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash, createCipheriv, randomBytes } from "node:crypto";
import { sealedSessionSecret } from "../lib/session-envelope";

test("existing signing secret survives sealed transport without coupling to admin password",()=> {
  const wrappingKey="test-only-wrapping-key-with-at-least-32-characters";
  const value="test-only-original-signing-secret-at-least-32-characters";
  const key=createHash("sha256").update("benchmark-session-wrap-v1\0").update(wrappingKey).digest();
  const iv=randomBytes(12);const cipher=createCipheriv("aes-256-gcm",key,iv);
  cipher.setAAD(Buffer.from("benchmark-session-secret-v1"));
  const ciphertext=Buffer.concat([cipher.update(value),cipher.final()]);
  const box={version:1,iv:iv.toString("base64"),tag:cipher.getAuthTag().toString("base64"),ciphertext:ciphertext.toString("base64")};
  const envelope=JSON.stringify(box);
  assert.equal(sealedSessionSecret(envelope,wrappingKey),value);
  assert.equal(sealedSessionSecret(envelope,wrappingKey),value);
  assert.throws(()=>sealedSessionSecret(envelope,wrappingKey+"wrong"));
  const bytes=Buffer.from(box.ciphertext,"base64");bytes[0]^=1;
  assert.throws(()=>sealedSessionSecret(JSON.stringify({...box,ciphertext:bytes.toString("base64")}),wrappingKey));
  assert.equal(sealedSessionSecret(undefined,wrappingKey),undefined);
});
