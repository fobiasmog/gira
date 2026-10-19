import { test } from "node:test"
import assert from "node:assert/strict"
import type { ErrorEvent } from "@sentry/vue"
import { scrubEvent } from "./scrub.ts"

const SECRETS = ["Top secret title", "Secret description", "secret@example.com", "Private comment"]

function sampleEvent(): ErrorEvent {
  return {
    type: undefined,
    event_id: "abc",
    exception: { values: [{ type: "TypeError", value: "x is undefined", stacktrace: { frames: [{ filename: "/vite/assets/app.js", lineno: 1 }] } }] },
    request: {
      url: "https://goalner.example/app/projects/7/tasks/GOAL-12",
      data: { title: "Top secret title" },
      cookies: { session_id: "s" },
      query_string: "q=Private comment",
    },
    user: { id: "42", email: "secret@example.com", username: "Secret", ip_address: "1.2.3.4" },
    extra: { description: "Secret description" },
    contexts: {
      vue: { componentName: "TaskPage", lifecycleHook: "render" },
      state: { state: { type: "pinia", value: { task: { title: "Top secret title" } } } },
    },
    breadcrumbs: [
      { category: "navigation", data: { from: "/app/", to: "/app/projects/7/tasks/GOAL-12" } },
      { category: "fetch", data: { method: "PATCH", url: "/api/projects/7/tasks/12", status_code: 200, request_body: "Secret description", response_body_size: 10 } },
      { category: "xhr", data: { method: "POST", url: "/api/x", status_code: 500, body: "Private comment" } },
      { category: "console", message: "secret@example.com" },
      { category: "ui.click", message: "button[aria-label=\"Top secret title\"]" },
      { category: "pinia.action", message: "Store: board | Action: move" },
    ],
  }
}

test("keeps the stack trace, URL, user id and safe context", () => {
  const event = scrubEvent(sampleEvent())
  assert.equal(event.exception?.values?.[0]?.stacktrace?.frames?.length, 1)
  assert.equal(event.request?.url, "https://goalner.example/app/projects/7/tasks/GOAL-12")
  assert.deepEqual(event.user, { id: "42" })
  assert.deepEqual(event.contexts?.vue, { componentName: "TaskPage", lifecycleHook: "render" })
  assert.deepEqual(event.breadcrumbs?.map((b) => b.category), ["navigation", "fetch", "xhr", "pinia.action"])
  assert.deepEqual(event.breadcrumbs?.[1]?.data, { method: "PATCH", url: "/api/projects/7/tasks/12", status_code: 200 })
})

test("removes everything that could hold what people wrote", () => {
  const json = JSON.stringify(scrubEvent(sampleEvent()))
  for (const secret of SECRETS) assert.ok(!json.includes(secret), `leaked ${secret}`)
  assert.ok(!json.includes("1.2.3.4"))
  assert.ok(!json.includes("session_id"))
})

test("an event without a user or breadcrumbs passes through", () => {
  const event = scrubEvent({ type: undefined, message: "boom" })
  assert.deepEqual(event, { type: undefined, message: "boom" })
})
