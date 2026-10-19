import { test } from "node:test"
import assert from "node:assert/strict"
import { columnDot, toneOf } from "./tones.ts"

test("a tone depends only on the id", () => {
  assert.equal(toneOf(42), toneOf(42))
  assert.equal(toneOf(6), 1)
  assert.equal(toneOf(7), 2)
  assert.equal(toneOf(11), 6)
})

test("consecutive ids spread over all six tones", () => {
  assert.deepEqual(new Set([100, 101, 102, 103, 104, 105].map(toneOf)), new Set([1, 2, 3, 4, 5, 6]))
  for (let id = 1; id < 50; id++) assert.notEqual(toneOf(id), toneOf(id + 1))
})

test("every id maps into 1–6", () => {
  for (const id of [0, 1, 5, 999_999_937, -3, 2.7]) assert.ok([1, 2, 3, 4, 5, 6].includes(toneOf(id)), String(id))
})

test("a column's valid hex colour is used as is", () => {
  assert.deepEqual(columnDot({ id: 1, color: "#1E7B45", done: false }), { kind: "color", color: "#1E7B45" })
  assert.deepEqual(columnDot({ id: 1, color: "#abc", done: true }), { kind: "color", color: "#abc" })
  assert.deepEqual(columnDot({ id: 1, color: " #abcdef ", done: false }), { kind: "color", color: "#abcdef" })
})

test("invalid colour strings are rejected", () => {
  for (const color of ["red", "#abcd", "#ggg", "abcdef", "#12345", "rgb(1 2 3)", "#fff;background:url(x)", "", null, undefined]) {
    assert.deepEqual(columnDot({ id: 7, color, done: false }), { kind: "tone", tone: toneOf(7) }, String(color))
  }
})

test("without a colour, the done column is green and others get their tone", () => {
  assert.deepEqual(columnDot({ id: 3, color: null, done: true }), { kind: "done" })
  assert.deepEqual(columnDot({ id: 3, color: "legacy-blue", done: true }), { kind: "done" })
  assert.deepEqual(columnDot({ id: 3, color: null, done: false }), { kind: "tone", tone: toneOf(3) })
})
