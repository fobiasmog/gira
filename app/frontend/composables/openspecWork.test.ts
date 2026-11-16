import { test } from "node:test"
import assert from "node:assert/strict"
import { unfinishedOpenspecWork } from "./openspecWork.ts"
import { pluralize } from "../i18n/format.ts"
import { en } from "../i18n/en.ts"
import { ru } from "../i18n/ru.ts"

const DONE = new Set([3])
const labels = { id: 1, name: "add-labels" }
const agents = { id: 2, name: "add-agents" }
const card = (status_id: number, openspec_change: { id: number; name: string } | null) => ({ status_id, openspec_change })

test("a sprint with unfinished OpenSpec cards: each change with its count, by name", () => {
  const tasks = [card(1, labels), card(2, labels), card(1, labels), card(3, labels), card(2, agents), card(1, null)]

  assert.deepEqual(unfinishedOpenspecWork(tasks, DONE), [
    { name: "add-agents", count: 1 },
    { name: "add-labels", count: 3 },
  ])
})

test("a sprint whose OpenSpec cards are all done: no warning", () => {
  assert.deepEqual(unfinishedOpenspecWork([card(3, labels), card(3, agents), card(1, null)], DONE), [])
})

test("an empty sprint: no warning", () => {
  assert.deepEqual(unfinishedOpenspecWork([], DONE), [])
})

test("the warning lines read naturally in both languages", () => {
  assert.equal(pluralize("en", 3, en.sprints.openspecUnfinished).replace("{count}", "3"), "{name}: 3 unfinished cards")
  assert.equal(pluralize("en", 1, en.sprints.openspecUnfinished).replace("{count}", "1"), "{name}: 1 unfinished card")
  assert.equal(pluralize("ru", 1, ru.sprints.openspecUnfinished).replace("{count}", "1"), "{name}: 1 незавершённая карточка")
  assert.equal(pluralize("ru", 3, ru.sprints.openspecUnfinished).replace("{count}", "3"), "{name}: 3 незавершённые карточки")
  assert.equal(pluralize("ru", 5, ru.sprints.openspecUnfinished).replace("{count}", "5"), "{name}: 5 незавершённых карточек")
})
