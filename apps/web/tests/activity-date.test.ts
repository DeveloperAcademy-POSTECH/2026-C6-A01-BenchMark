import { test } from "node:test";
import assert from "node:assert/strict";
import { activityKoreaTime } from "../src/lib/activity";
test("Korean date formatting crosses day, month, leap-day and year boundaries", () => {
  for (const [utc, expected] of [
    ["2026-09-16T14:59:59.999Z", "2026-09-16T23:59:59.999+09:00"],
    ["2026-09-16T15:00:00.000Z", "2026-09-17T00:00:00.000+09:00"],
    ["2026-12-31T15:00:00.000Z", "2027-01-01T00:00:00.000+09:00"],
    ["2028-02-28T15:00:00.000Z", "2028-02-29T00:00:00.000+09:00"],
  ]) assert.equal(activityKoreaTime(utc), expected);
});
