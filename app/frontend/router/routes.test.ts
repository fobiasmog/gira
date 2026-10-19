import { test } from "node:test"
import assert from "node:assert/strict"
import { parseId } from "./routes.ts"

test("parseId accepts positive integers only", () => {
  assert.equal(parseId("7"), 7)
  assert.equal(parseId(["12"]), 12)
  for (const value of ["0", "-1", "07", "1.5", "abc", "", undefined, null, ["x"]]) {
    assert.equal(parseId(value), null, String(value))
  }
})
