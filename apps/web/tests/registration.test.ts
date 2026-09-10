import test from "node:test";
import assert from "node:assert/strict";
import { registrationSchema, formVersion } from "../src/lib/registration";
const input = { name: "  테스트  ", phone: "010-0000-1234", consent: true, formVersion };
test("trims names and normalizes domestic and international numbers", () => {
  assert.equal(registrationSchema.parse(input).name, "테스트");
  for (const phone of ["010-0000-1234", "+82 10 0000 1234", "+82 (0)10 0000 1234"]) {
    assert.equal(registrationSchema.parse({ ...input, phone }).phone, "01000001234");
  }
});
test("rejects invalid fields, missing consent and unknown answers", () => {
  for (const patch of [{ phone: "abc01000001234" }, { phone: "010123" }, { name: " " }, { name: "a\u0000b" }, { consent: false }, { formVersion: 0 }, { email: "unexpected" }]) {
    assert.equal(registrationSchema.safeParse({ ...input, ...patch }).success, false);
  }
});
