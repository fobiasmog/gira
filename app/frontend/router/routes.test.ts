import { test } from "node:test"
import assert from "node:assert/strict"
import { createMemoryHistory, createRouter } from "vue-router"
import { boardLocation, parseId, routes } from "./routes.ts"
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

test("the sections: Board, Changes, Members, Agents, Archive and Settings, without backlog, sprints or milestones", () => {
  assert.deepEqual(projectSections.map((section) => section.name), ["board", "changes", "members", "agents", "archive", "project-settings"])
  const names = routes.map((route) => String(route.name))
  assert.deepEqual(names.filter((name) => /backlog|sprint|milestone/.test(name)), [])
})

test("a route's section", () => {
  assert.equal(sectionOf("task")?.name, "board")
  for (const name of ["board-list", "board-change", "board-other", "board-list-change", "board-list-other"]) {
    assert.equal(sectionOf(name)?.name, "board", name)
  }
  assert.equal(sectionOf("changes")?.name, "changes")
  assert.equal(sectionOf("archived-task")?.name, "archive")
  assert.equal(sectionOf("dashboard"), null)
  assert.equal(sectionOf(undefined), null)
})

test("each board tab has an address in both layouts, and a change named other keeps its own", () => {
  const router = createRouter({ history: createMemoryHistory(), routes })
  const href = (location: Parameters<typeof router.resolve>[0]) => router.resolve(location).href

  assert.equal(href(boardLocation(3, "kanban", { kind: "default" })), "/projects/3/board")
  assert.equal(href(boardLocation(3, "kanban", { kind: "other" })), "/projects/3/board/other")
  assert.equal(href(boardLocation(3, "kanban", { kind: "change", name: "add-labels" })), "/projects/3/board/changes/add-labels")
  assert.equal(href(boardLocation(3, "kanban", { kind: "change", name: "other" })), "/projects/3/board/changes/other")
  assert.equal(href(boardLocation(3, "list", { kind: "default" })), "/projects/3/list")
  assert.equal(href(boardLocation(3, "list", { kind: "other" })), "/projects/3/list/other")
  assert.equal(href(boardLocation(3, "list", { kind: "change", name: "add-labels" })), "/projects/3/list/changes/add-labels")
})

test("a board address gives the page its layout and tab", () => {
  const router = createRouter({ history: createMemoryHistory(), routes })
  const props = (path: string) => {
    const route = router.resolve(path)
    const record = route.matched.at(-1)!
    return (record.props.default as (route: unknown) => Record<string, unknown>)(route)
  }

  assert.deepEqual(props("/projects/3/board"), { projectId: 3, layout: "kanban", tab: { kind: "default" } })
  assert.deepEqual(props("/projects/3/list/other"), { projectId: 3, layout: "list", tab: { kind: "other" } })
  assert.deepEqual(props("/projects/3/board/changes/export-csv"), { projectId: 3, layout: "kanban", tab: { kind: "change", name: "export-csv" } })
})
