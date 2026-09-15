import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { activityEvent, csvActivity, publicPath } from "../src/lib/activity";
const story = randomUUID();
const event = { id: randomUUID(), visitId: randomUUID(), sessionId: randomUUID(), occurredAt: new Date().toISOString(), path: `/stories/${story}`, storyId: story, name: "page_view", properties: {} };
test("strict activity allowlist excludes private fields, URLs and event properties", () => {
  assert.ok(activityEvent.safeParse(event).success);
  for (const key of ["phone", "email", "displayName", "story", "photo", "authorization", "referrer"]) {
    assert.equal(activityEvent.safeParse({ ...event, [key]: "private" }).success, false);
    assert.equal(activityEvent.safeParse({ ...event, properties: { [key]: "private" } }).success, false);
  }
  for (const path of ["/admin", "/reserve?phone=01012345678", "/stories?utm_source=private", "/api/reservations", "https://example.com"]) assert.equal(publicPath.safeParse(path).success, false);
  assert.equal(activityEvent.safeParse({ ...event, storyId: randomUUID() }).success, false);
  assert.equal(activityEvent.safeParse({ ...event, name: "donation_success" }).success, false);
});
test("scroll buckets, foreground deltas and action semantics are bounded", () => {
  for (const percent of [25,50,75,100]) assert.ok(activityEvent.safeParse({ ...event, name: "scroll_depth", properties: { percent } }).success);
  for (const percent of [0,24,101,"25"]) assert.equal(activityEvent.safeParse({ ...event, name: "scroll_depth", properties: { percent } }).success, false);
  for (const milliseconds of [-1,0,60001,1.5]) assert.equal(activityEvent.safeParse({ ...event, name: "active_time", properties: { milliseconds } }).success, false);
  assert.ok(activityEvent.safeParse({ ...event, name: "active_time", properties: { milliseconds: 15000 } }).success);
  assert.equal(activityEvent.safeParse({ ...event, name: "reservation_success" }).success, false);
  assert.ok(activityEvent.safeParse({ ...event, path: "/reserve", name: "reservation_success" }).success);
});
test("CSV uses fixed columns and quoted JSON, with no user free text", () => {
  const csv = csvActivity([{ id: event.id, visit_id: event.visitId, session_id: event.sessionId, name: "scroll_depth", occurred_at: event.occurredAt, received_at: event.occurredAt, path: event.path, story_id: story, properties: { percent: 25 } }]);
  assert.ok(csv.startsWith('\uFEFF"event_id"'));
  assert.ok(csv.includes('"{""percent"":25}"'));
  assert.equal(csv.split("\r\n").length, 2);
});
test("camera telemetry contains outcomes without image or error contents", () => {
  for (const name of ["camera_ready", "photo_capture_success", "photo_share_cancelled", "photo_download_click"]) {
    assert.ok(activityEvent.safeParse({ ...event, path: "/camera", name }).success);
    assert.equal(activityEvent.safeParse({ ...event, path: "/camera", name, properties: { filename: "private.jpg" } }).success, false);
    assert.equal(activityEvent.safeParse({ ...event, name }).success, false);
  }
});
