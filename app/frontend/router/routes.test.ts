import { test } from "node:test"
import assert from "node:assert/strict"
import { parseId, routes } from "./routes.ts"
import { projectSections, sectionOf } from "./sections.ts"

test("parseId accepts positive integers only", () => {
  assert.equal(parseId("7"), 7)
  assert.equal(parseId(["12"]), 12)
  for (const value of ["0", "-1", "07", "1.5", "abc", "", undefined, null, ["x"]]) {
    assert.equal(parseId(value), null, String(value))
  }
})

test("every project section and the routes inside it exist, and each route belongs to one section", () => {
  const names = new Set(routes.map((route) => route.name))
  const inside = projectSections.flatMap((section) => [section.name, ...(section.also ?? [])])
  for (const name of inside) assert.ok(names.has(name), name)
  assert.equal(new Set(inside).size, inside.length)
})

test("a route's section", () => {
  assert.equal(sectionOf("task")?.name, "board")
  assert.equal(sectionOf("board-list")?.name, "board")
  assert.equal(sectionOf("archived-task")?.name, "archive")
  assert.equal(sectionOf("dashboard"), null)
  assert.equal(sectionOf(undefined), null)
})
