import { test } from "node:test"
import assert from "node:assert/strict"
import { dropIndex, edgeScrollDelta, isNoop } from "./dragMath.ts"

const midpoints = [50, 150, 250]

test("before the first item", () => {
  assert.equal(dropIndex(10, midpoints), 0)
  assert.equal(dropIndex(50, midpoints), 0)
})

test("between items", () => {
  assert.equal(dropIndex(51, midpoints), 1)
  assert.equal(dropIndex(149, midpoints), 1)
  assert.equal(dropIndex(200, midpoints), 2)
})

test("after the last item, at the last position", () => {
  assert.equal(dropIndex(251, midpoints), 3)
  assert.equal(dropIndex(10_000, midpoints), 3)
})

test("an empty container", () => {
  assert.equal(dropIndex(0, []), 0)
  assert.equal(dropIndex(500, []), 0)
})

test("a single item", () => {
  assert.equal(dropIndex(10, [100]), 0)
  assert.equal(dropIndex(110, [100]), 1)
})

test("dropping back at the starting place is a no-op", () => {
  assert.equal(isNoop("todo", 1, "todo", 1), true)
  assert.equal(isNoop("todo", 1, "todo", 2), false)
  assert.equal(isNoop("todo", 1, "work", 1), false)
})

test("edge scrolling speeds up towards the edges and stops in the middle", () => {
  assert.equal(edgeScrollDelta(500, 0, 1000), 0)
  assert.ok(edgeScrollDelta(990, 0, 1000) > edgeScrollDelta(960, 0, 1000))
  assert.ok(edgeScrollDelta(960, 0, 1000) > 0)
  assert.ok(edgeScrollDelta(5, 0, 1000) < edgeScrollDelta(40, 0, 1000))
  assert.ok(edgeScrollDelta(40, 0, 1000) < 0)
  assert.equal(edgeScrollDelta(1200, 0, 1000), 18)
  assert.equal(edgeScrollDelta(50, 0, 80), 0)
})
