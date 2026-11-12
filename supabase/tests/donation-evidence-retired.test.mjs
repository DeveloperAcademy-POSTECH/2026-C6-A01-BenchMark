import assert from "node:assert/strict";
import test from "node:test";

test("both legacy AI functions reject submissions without reading or forwarding them", async (t) => {
  const handlers = [];
  t.mock.method(globalThis, "fetch", () => assert.fail("A retired function must never fetch"));
  globalThis.Deno = { serve: (handler) => handlers.push(handler) };
  t.after(() => { delete globalThis.Deno; });

  await import("../functions/analyze-donation-evidence/index.ts");
  await import("../functions/analyze-evidence/index.ts");
  assert.equal(handlers.length, 2);
  for (const handler of handlers) {
    const request = new Request("https://example.test/functions/v1/legacy-analysis", {
      method: "POST",
      body: JSON.stringify({ evidence_id: "synthetic-retired-request" }),
    });
    const response = await handler(request);
    assert.equal(response.status, 410);
    assert.equal(response.headers.get("cache-control"), "no-store");
    assert.equal(request.bodyUsed, false);
    assert.deepEqual(await response.json(), { error: "donation_evidence_retired" });
  }
});
