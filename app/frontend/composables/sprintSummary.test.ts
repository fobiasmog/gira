import { test } from "node:test"
import assert from "node:assert/strict"
import { sprintSummary } from "./sprintSummary.ts"
import { formatDateRange, pluralize } from "../i18n/format.ts"
import { en } from "../i18n/en.ts"
import { ru } from "../i18n/ru.ts"

// A time zone with daylight saving time, so the DST case below means
// something on machines and CI runners set to UTC. Node applies a TZ change
// to Date objects created afterwards.
process.env.TZ = "Europe/Berlin"

const columns = [{ id: 1, done: false }, { id: 2, done: false }, { id: 3, done: true }]
const tasks = (open: number, done: number) => [
  ...Array.from({ length: open }, (_, i) => ({ status_id: i % 2 ? 1 : 2 })),
  ...Array.from({ length: done }, () => ({ status_id: 3 })),
]

test("a running sprint: done out of all tasks on the board, and days left", () => {
  const summary = sprintSummary({ ends_on: "2026-10-26" }, columns, tasks(9, 3), new Date(2026, 9, 19, 9, 30))
  assert.deepEqual(summary, { done: 3, total: 12, daysLeft: 7, state: "running" })
})

test("the time of day does not change the count", () => {
  for (const hour of [0, 12, 23]) {
    assert.equal(sprintSummary({ ends_on: "2026-10-26" }, columns, [], new Date(2026, 9, 19, hour, 59)).daysLeft, 7)
  }
})

test("the end date is the sprint's last day", () => {
  const summary = sprintSummary({ ends_on: "2026-10-26" }, columns, tasks(1, 1), new Date(2026, 9, 26, 18))
  assert.deepEqual(summary, { done: 1, total: 2, daysLeft: 0, state: "last-day" })
})

test("after the end date the sprint has ended", () => {
  const summary = sprintSummary({ ends_on: "2026-10-26" }, columns, [], new Date(2026, 9, 27, 0, 5))
  assert.deepEqual(summary, { done: 0, total: 0, daysLeft: 0, state: "ended" })
})

test("a range across a DST change counts calendar days", () => {
  // Clocks go back on 25 October 2026 and forward on 29 March 2026 in Berlin.
  assert.equal(sprintSummary({ ends_on: "2026-10-30" }, columns, [], new Date(2026, 9, 20, 23, 30)).daysLeft, 10)
  assert.equal(sprintSummary({ ends_on: "2026-04-02" }, columns, [], new Date(2026, 2, 27, 0, 30)).daysLeft, 6)
})

test("tasks without a column do not count as done", () => {
  assert.deepEqual(sprintSummary({ ends_on: "2026-10-26" }, columns, [{ status_id: null }, { status_id: 3 }], new Date(2026, 9, 19)).done, 1)
})

test("days left in English and Russian", () => {
  assert.equal(pluralize("en", 1, en.board.sprint.daysLeft), "1 day left")
  assert.equal(pluralize("en", 7, en.board.sprint.daysLeft), "7 days left")
  assert.equal(pluralize("ru", 1, ru.board.sprint.daysLeft), "остался 1 день")
  assert.equal(pluralize("ru", 3, ru.board.sprint.daysLeft), "осталось 3 дня")
  assert.equal(pluralize("ru", 5, ru.board.sprint.daysLeft), "осталось 5 дней")
  assert.equal(pluralize("ru", 21, ru.board.sprint.daysLeft), "остался 21 день")
})

test("the sprint's dates as one range", () => {
  const now = new Date(2026, 9, 19)
  for (const lang of ["en", "ru"] as const) {
    const range = formatDateRange(lang, "2026-10-13", "2026-10-26", now)
    assert.match(range, /13/, range)
    assert.match(range, /26/, range)
    assert.doesNotMatch(range, /2026/, range)
  }
  assert.match(formatDateRange("en", "2026-12-28", "2027-01-08", now), /2027/)
})
