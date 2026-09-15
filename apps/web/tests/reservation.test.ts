import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { reservationDetailsInput, reservationInput } from "../src/lib/reservation";
import { activityEvent } from "../src/lib/activity";
const details = { email: "donor@example.test", displayName: "검증용", title: "검증", story: "스토리", paymentMethod: "deposit", amount: "3000" };
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

const valid = { ...details, id: randomUUID(), reason: "rest", displayName: "신청자" };

test("anonymous reservations normalize omitted, empty and submitted names", () => {
  for (const displayName of [undefined, "", "실명 입력", "a".repeat(41)]) {
    const result = reservationInput.parse({ ...valid, isAnonymous: "true", displayName });
    assert.equal(result.displayName, "익명");
    assert.equal("phone" in result, false);
  }
});

test("named and legacy reservations still require a valid name", () => {
  for (const isAnonymous of [undefined, "false"]) {
    assert.equal(reservationInput.parse({ ...valid, isAnonymous }).displayName, "신청자");
    for (const displayName of [undefined, "", "   ", "a".repeat(41)]) {
      assert.equal(reservationInput.safeParse({ ...valid, isAnonymous, displayName }).success, false);
    }
  }
});

test("anonymous selection rejects invalid flags and still requires story", () => {
  for (const isAnonymous of ["on", "yes", true, 1, null]) {
    assert.equal(reservationInput.safeParse({ ...valid, isAnonymous }).success, false);
  }
  for (const invalid of [{ story: "" }, { title: "" }]) {
    assert.equal(reservationInput.safeParse({ ...valid, isAnonymous: "true", ...invalid }).success, false);
  }
});

test("new submissions omit phone and strip legacy supplied contact fields", () => {
  for (const phone of [undefined, "", "010-0000-0000", "invalid"]) {
    const result = reservationInput.parse({ ...valid, phone });
    assert.equal("phone" in result, false);
  }
});

test("email is required, validated and trimmed, including anonymous submissions", () => {
  for (const email of [undefined, "", "invalid", "a".repeat(243) + "@example.test"]) {
    assert.equal(reservationInput.safeParse({ ...valid, isAnonymous: "true", email }).success, false);
  }
  assert.equal(reservationInput.parse({ ...valid, email: " donor@example.test " }).email, "donor@example.test");
});
