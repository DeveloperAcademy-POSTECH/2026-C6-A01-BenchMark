import { test } from "node:test";
import assert from "node:assert/strict";
import { reservationInput } from "../src/lib/reservation";

const input = {
  id: "8ee39046-7fe0-4a51-9857-2a48f2d0792b", displayName: "신청자", phone: "010-0000-0000",
  reason: "rest", title: "쉬어 가세요", story: "작은 쉼을 선물합니다.", paymentMethod: "deposit", amount: "3000",
};

test("anonymous reservations normalize omitted, empty and submitted names", () => {
  for (const displayName of [undefined, "", "실명 입력", "a".repeat(41)]) {
    const result = reservationInput.parse({ ...input, isAnonymous: "true", displayName });
    assert.equal(result.displayName, "익명");
    assert.equal(result.phone, "01000000000");
  }
});

test("named and legacy reservations still require a valid name", () => {
  for (const isAnonymous of [undefined, "false"]) {
    assert.equal(reservationInput.parse({ ...input, isAnonymous }).displayName, "신청자");
    for (const displayName of [undefined, "", "   ", "a".repeat(41)]) {
      assert.equal(reservationInput.safeParse({ ...input, isAnonymous, displayName }).success, false);
    }
  }
});

test("anonymous selection rejects invalid flags and still requires contact and story", () => {
  for (const isAnonymous of ["on", "yes", true, 1, null]) {
    assert.equal(reservationInput.safeParse({ ...input, isAnonymous }).success, false);
  }
  for (const invalid of [{ phone: "" }, { story: "" }, { title: "" }]) {
    assert.equal(reservationInput.safeParse({ ...input, isAnonymous: "true", ...invalid }).success, false);
  }
});
