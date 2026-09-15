import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { reservationDetailsInput, reservationInput } from "../src/lib/reservation";
import { activityEvent } from "../src/lib/activity";
const details = { displayName: "검증용", phone: "010-0000-0015", title: "검증", story: "스토리", paymentMethod: "deposit", amount: "3000" };
test("only offered reservation amounts are accepted by the shared client/server schema", () => {
  for (const amount of [3000,5000,"3000","5000"]) assert.equal(reservationDetailsInput.safeParse({ ...details, amount }).success, true);
  for (const amount of [undefined,"",0,1,7200,3000.5,-3000,"other"]) assert.equal(reservationDetailsInput.safeParse({ ...details, amount }).success, false);
});
test("details can open the reason question but final submission still requires a reason", () => {
  assert.equal(reservationDetailsInput.safeParse(details).success, true);
  const final = { ...details, id: randomUUID() };
  assert.equal(reservationInput.safeParse(final).success, false);
  assert.equal(reservationInput.safeParse({ ...final, reason: "story" }).success, true);
  assert.equal(reservationInput.safeParse({ ...final, reason: "other", reasonOther: "   " }).success, false);
  assert.equal(reservationInput.safeParse({ ...final, reason: "other", reasonOther: "검증 이유" }).success, true);
});
test("reason-open analytics reports only the step and never the response", () => {
  const base = { id: randomUUID(), visitId: randomUUID(), sessionId: randomUUID(), occurredAt: new Date().toISOString(), path: "/reserve", properties: {} };
  for (const name of ["reservation_submit_click", "reservation_reason_opened"]) {
    assert.equal(activityEvent.safeParse({ ...base, name }).success, true);
    assert.equal(activityEvent.safeParse({ ...base, name, properties: { reasonOther: "private" } }).success, false);
  }
});
