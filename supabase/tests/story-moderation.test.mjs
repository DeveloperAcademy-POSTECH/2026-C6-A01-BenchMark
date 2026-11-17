import assert from "node:assert/strict";
import test from "node:test";
import { createStoryModerationHandler, withEducationBrowserAccess } from "../functions/moderate-story/handler.ts";

const user = "a3880000-0000-4000-8000-000000000001";
const session = "a3880000-0000-4000-8000-000000000021";
const storyId = "a3880000-0000-4000-8000-000000000011";
const root = `${user}/${storyId}`;
const snapshot = "a".repeat(64);
const jwt = `fixture.${Buffer.from(JSON.stringify({ sub: user, role: "authenticated", session_id: session })).toString("base64url")}.signature`;

function setup({ finding = { reason: null, source: null }, failAt, resolution = 200, education = false } = {}) {
  const calls = [];
  const draft = {
    title: "A campus walk", body: "A quiet day in autumn", cucumber_name: "잎새",
    snapshot, photos: [`${root}/photo.jpg`], appearance: [`${root}/appearance/look/top.png`],
    cards: [`${root}/card/card.png`, `${root}/card/card/cover.jpg`],
  };
  if (education) {
    delete draft.cucumber_name; draft.display_name = "Synthetic author"; draft.appearance = [];
    draft.photos = [`${user}/education/${storyId}/photos/photo.jpg`];
    draft.cards = ["card.png", "card/back.png", "card/front-preview.png", "card/back-preview.png"].map(path =>
      `${user}/education/${storyId}/card/${path}`);
  }
  const expected = { id: storyId, revision: 1, ai_review_consent_version: 1, ...(education ? { scope: "education" } : {}) };
  const images = [...draft.photos, ...draft.appearance, ...draft.cards];
  const handler = createStoryModerationHandler({
    supabaseUrl: "https://project.test", anonKey: "test-anon", serviceKey: "test-service", openaiKey: "test-openai",
  }, async (url, options) => {
    const target = new URL(url);
    const body = options.body === undefined ? undefined : JSON.parse(options.body);
    if (target.pathname === "/auth/v1/user") {
      calls.push("auth");
      assert.equal(options.headers.Authorization, `Bearer ${jwt}`);
      return failAt === "auth" || (failAt === "reauth" && calls.filter((call) => call === "auth").length === 2)
        ? Response.json({}, { status: 401 }) : Response.json({ id: user });
    }
    if (target.pathname === (education ? "/rest/v1/rpc/oi_moderate_education_story" : "/rest/v1/rpc/oi_moderate_story")) {
      assert.equal(options.headers.Authorization, "Bearer test-service");
      assert.equal(body.p_user, user);
      assert.equal(body.p_session, session);
      assert.deepEqual(body.p_submission, expected);
      if ("p_snapshot" in body) {
        calls.push("complete");
        assert.equal(body.p_snapshot, snapshot);
        assert.equal(body.p_reason, finding.reason);
        assert.equal(body.p_source, finding.source);
        return Response.json({
          story_id: storyId, revision: finding.reason ? 1 : 2,
          status: finding.reason ? "rejected" : "approved", reason: finding.reason, source: finding.source,
          story: finding.reason ? null : { id: storyId, revision: 2, status: education ? "published" : "draft" },
        }, { status: resolution });
      }
      calls.push("prepare");
      return failAt === "ownership" ? Response.json({}, { status: 403 }) : Response.json(draft);
    }
    if (target.pathname === "/storage/v1/object/sign/oi-story-media") {
      calls.push("sign");
      assert.deepEqual(body.paths, images);
      assert.equal(body.expiresIn, 90);
      const signed = images.map((path) => ({ path, signedURL: `/object/sign/oi-story-media/${path}?token=fixture` }));
      if (failAt === "sign") signed[0].signedURL = "https://external.test/no";
      return Response.json(signed);
    }
    assert.equal(target.href, "https://api.openai.com/v1/responses");
    calls.push("analysis");
    assert.equal(options.headers.Authorization, "Bearer test-openai");
    assert.equal(body.store, false);
    assert.equal(body.text.format.name, "story_publication_review");
    const content = body.input[0].content;
    assert.deepEqual(JSON.parse(content[0].text), { title: draft.title, body: draft.body,
      ...(education ? { display_name: draft.display_name } : { cucumber_name: draft.cucumber_name }) });
    assert.deepEqual(content.filter((part) => part.type === "input_image").map((part) => part.image_url),
      images.map((path) => `https://project.test/storage/v1/object/sign/oi-story-media/${path}?token=fixture`));
    if (failAt === "provider") return Response.json({}, { status: 429 });
    const output = failAt === "refusal" ? { type: "refusal" } : { type: "output_text", text: JSON.stringify(finding) };
    return Response.json({ status: "completed", output: [{ type: "message", role: "assistant", content: [output] }] });
  });
  const submit = (consent = 1) => handler(new Request("https://project.test/moderate-story", {
    method: "POST", headers: { authorization: `Bearer ${jwt}` }, body: JSON.stringify({ ...expected, ai_review_consent_version: consent }),
  }));
  return { calls, submit };
}

test("records approval of the private draft after analyzing all images", async () => {
  const { calls, submit } = setup();
  const response = await submit();
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { story_id: storyId, revision: 2, status: "approved", reason: null, source: null,
    story: { id: storyId, revision: 2, status: "draft" } });
  assert.deepEqual(calls, ["auth", "prepare", "sign", "analysis", "auth", "complete"]);
});

test("returns only the bounded rejection reason and leaves the draft untouched", async () => {
  const { calls, submit } = setup({ finding: { reason: "privacy", source: "card" } });
  assert.deepEqual(await (await submit()).json(), { story_id: storyId, revision: 1, status: "rejected", reason: "privacy", source: "card", story: null });
  assert.deepEqual(calls, ["auth", "prepare", "sign", "analysis", "auth", "complete"]);
});

test("returns distinct refusal reasons for unintelligible stories and profanity", async () => {
  for (const reason of ["unintelligible", "profanity"]) {
    const finding = { reason, source: "story" };
    const { calls, submit } = setup({ finding });
    const response = await submit();
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { story_id: storyId, revision: 1, status: "rejected", ...finding, story: null });
    assert.ok(calls.includes("complete"));
  }
});

test("authorization, image access, provider failure and malformed verdicts never publish", async () => {
  for (const [updates, status] of [
    [{ failAt: "auth" }, 401], [{ failAt: "reauth" }, 401], [{ failAt: "ownership" }, 403],
    [{ failAt: "sign" }, 503], [{ failAt: "provider" }, 503], [{ failAt: "refusal" }, 503],
    [{ finding: { reason: null, source: "story" } }, 503],
  ]) {
    const { calls, submit } = setup(updates);
    assert.equal((await submit()).status, status, JSON.stringify(updates));
    assert.ok(!calls.includes("complete"));
  }
});

test("a changed snapshot returns a conflict instead of saying the story was published", async () => {
  const { submit } = setup({ resolution: 409 });
  const response = await submit();
  assert.equal(response.status, 409);
  assert.equal((await response.json()).status, undefined);
});

test("does not read a draft or call OpenAI before explicit consent", async () => {
  const { calls, submit } = setup();
  assert.equal((await submit(null)).status, 400);
  assert.deepEqual(calls, ["auth"]);
});

test("education analyzes its photo and four card images through the education-only RPC", async () => {
  const { calls, submit } = setup({ education: true });
  assert.equal((await (await submit()).json()).story.status, "published");
  assert.deepEqual(calls, ["auth", "prepare", "sign", "analysis", "auth", "complete"]);
});

test("education browser preflight uses the exact site origin and cannot bypass bearer authentication", async () => {
  const origin = "https://postech-lights-together.wpwnshrck.chatgpt.site";
  const endpoint = "https://project.test/moderate-story";
  const handler = withEducationBrowserAccess(createStoryModerationHandler({}));
  const denied = await handler(new Request(endpoint, { method: "OPTIONS", headers: { origin: "https://other.test" } }));
  assert.equal(denied.status, 403);
  const preflight = await handler(new Request(endpoint, { method: "OPTIONS", headers: { origin } }));
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get("access-control-allow-origin"), origin);
  const post = await handler(new Request(endpoint, { method: "POST", headers: { origin } }));
  assert.equal(post.status, 401);
  assert.equal(post.headers.get("access-control-allow-origin"), origin);
});
