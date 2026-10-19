import { test } from "node:test"
import assert from "node:assert/strict"
import { en } from "./en.ts"
import { ru } from "./ru.ts"
import { calendarDaysFrom, formatRelativeDay, fromDateTimeInput, pluralize, toDateTimeInput } from "./format.ts"

function shape(node: unknown, prefix = ""): string[] {
  if (typeof node === "string") return [prefix]
  const entries = Object.entries(node as Record<string, unknown>)
  if ("other" in (node as object)) return [`${prefix}(plural)`]
  return entries.flatMap(([key, value]) => shape(value, prefix ? `${prefix}.${key}` : key))
}

test("en and ru have the same keys", () => {
  assert.deepEqual(shape(ru).sort(), shape(en).sort())
})

test("no translation is empty", () => {
  for (const dictionary of [en, ru]) {
    const strings = JSON.stringify(dictionary).match(/"[^"]*":""/g)
    assert.equal(strings, null)
  }
})

test("Russian plural forms", () => {
  const forms = ru.board.taskCount
  assert.equal(pluralize("ru", 1, forms), "1 задача")
  assert.equal(pluralize("ru", 3, forms), "3 задачи")
  assert.equal(pluralize("ru", 5, forms), "5 задач")
  assert.equal(pluralize("ru", 21, forms), "21 задача")
  assert.equal(pluralize("ru", 1.5, forms), "1,5 задачи")
})

test("English plural forms", () => {
  assert.equal(pluralize("en", 1, en.board.taskCount), "1 task")
  assert.equal(pluralize("en", 3, en.board.taskCount), "3 tasks")
  assert.equal(pluralize("en", 1000, en.board.taskCount), "1,000 tasks")
})

const now = new Date(2026, 9, 18, 23, 30)

test("relative days use the language's words", () => {
  assert.equal(formatRelativeDay("ru", new Date(2026, 9, 19, 0, 15), now), "завтра")
  assert.equal(formatRelativeDay("ru", new Date(2026, 9, 18, 8, 0), now), "сегодня")
  assert.equal(formatRelativeDay("ru", new Date(2026, 9, 17, 12, 0), now), "вчера")
  assert.equal(formatRelativeDay("en", new Date(2026, 9, 19, 9, 0), now), "tomorrow")
  assert.equal(formatRelativeDay("en", new Date(2026, 9, 18, 9, 0), now), "today")
  assert.equal(formatRelativeDay("en", new Date(2026, 9, 17, 9, 0), now), "yesterday")
})

test("further dates are formatted for the language, with the year only when it differs", () => {
  assert.equal(formatRelativeDay("en", new Date(2026, 9, 25), now), "Oct 25")
  assert.equal(formatRelativeDay("ru", new Date(2026, 9, 25), now), "25 окт.")
  assert.equal(formatRelativeDay("en", new Date(2027, 0, 2), now), "Jan 2, 2027")
})

test("calendar days ignore the time of day", () => {
  assert.equal(calendarDaysFrom(new Date(2026, 9, 18, 23, 59), new Date(2026, 9, 19, 0, 1)), 1)
  assert.equal(calendarDaysFrom(new Date(2026, 2, 28, 12), new Date(2026, 2, 30, 12)), 2)
})

test("datetime-local values round-trip through ISO timestamps in local time", () => {
  const iso = new Date(2026, 9, 19, 9, 5).toISOString()
  assert.equal(toDateTimeInput(iso), "2026-10-19T09:05")
  assert.equal(fromDateTimeInput("2026-10-19T09:05"), iso)
  assert.equal(toDateTimeInput(null), "")
  assert.equal(fromDateTimeInput(""), null)
})
