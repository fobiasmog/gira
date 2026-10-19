import { test, beforeEach } from "node:test"
import assert from "node:assert/strict"
import { ApiError, api, request } from "./client.ts"

interface Call { url: string; init: RequestInit }
let calls: Call[]
let navigatedTo: string | null

function respond(status: number, body?: unknown) {
  globalThis.fetch = async (input, init = {}) => {
    calls.push({ url: String(input), init })
    return new Response(body === undefined ? null : JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json" },
    })
  }
}

beforeEach(() => {
  calls = []
  navigatedTo = null
  Object.assign(globalThis, {
    document: { querySelector: () => ({ content: "csrf-123" }) },
    location: { href: "http://example.test/app/projects/7/tasks/GOAL-12", assign: (u: string) => { navigatedTo = u } },
  })
})

test("success: JSON body, headers, credentials and query string", async () => {
  respond(200, { id: 1, title: "Goal" })
  const project = await api.patch<{ id: number }>("/projects/1", { title: "Goal" })

  assert.deepEqual(project, { id: 1, title: "Goal" })
  const { url, init } = calls[0]!
  assert.equal(url, "/api/projects/1")
  assert.equal(init.method, "PATCH")
  assert.equal(init.credentials, "same-origin")
  assert.equal(init.body, JSON.stringify({ title: "Goal" }))
  const headers = init.headers as Record<string, string>
  assert.equal(headers["X-CSRF-Token"], "csrf-123")
  assert.equal(headers["Content-Type"], "application/json")
  assert.equal(headers.Accept, "application/json")

  respond(200, [])
  await api.get("/projects/1/tasks", { view: "backlog", user_id: undefined })
  assert.equal(calls[1]!.url, "/api/projects/1/tasks?view=backlog")
  assert.equal((calls[1]!.init.headers as Record<string, string>)["X-CSRF-Token"], undefined)
})

test("204 resolves to undefined", async () => {
  respond(204)
  assert.equal(await api.delete("/projects/1"), undefined)
})

test("FormData is sent without a JSON content type", async () => {
  respond(201, { id: 3 })
  const form = new FormData()
  form.append("body", "hi")
  await api.post("/projects/1/tasks/2/comments", form)
  assert.equal(calls[0]!.init.body, form)
  assert.equal((calls[0]!.init.headers as Record<string, string>)["Content-Type"], undefined)
})

test("401 navigates to the current URL and never settles", async () => {
  respond(401, { error: { code: "unauthorized", message: "Sign in to continue." } })
  const outcome = await Promise.race([
    api.patch("/projects/7/tasks/GOAL-12", { title: "x" }).then(() => "settled", () => "settled"),
    new Promise((resolve) => setTimeout(() => resolve("pending"), 20)),
  ])
  assert.equal(outcome, "pending")
  assert.equal(navigatedTo, "http://example.test/app/projects/7/tasks/GOAL-12")
})

test("422 carries the field errors", async () => {
  respond(422, { error: { code: "validation_failed", message: "Some fields are invalid.", fields: { short_name: ["Short name is invalid"] } } })
  await assert.rejects(api.post("/projects", { short_name: "!" }), (error: unknown) => {
    assert.ok(error instanceof ApiError)
    assert.equal(error.status, 422)
    assert.equal(error.code, "validation_failed")
    assert.deepEqual(error.fields, { short_name: ["Short name is invalid"] })
    return true
  })
})

test("429 is a rate_limited error", async () => {
  respond(429, { error: { code: "rate_limited", message: "Too many requests. Try again later." } })
  await assert.rejects(api.post("/feedback", {}), { name: "ApiError", status: 429, code: "rate_limited" })
})

test("500 without an envelope is an internal_error", async () => {
  globalThis.fetch = async () => new Response("<html>oops</html>", { status: 500 })
  await assert.rejects(api.get("/me"), { name: "ApiError", status: 500, code: "internal_error" })
})

test("a network failure is a network error", async () => {
  globalThis.fetch = async () => { throw new TypeError("Failed to fetch") }
  await assert.rejects(api.get("/me"), { name: "ApiError", status: 0, code: "network" })
})

test("a request that takes too long is a timeout error", async () => {
  globalThis.fetch = (_input, init) => new Promise((_resolve, reject) => {
    init?.signal?.addEventListener("abort", () => reject(init.signal?.reason))
  })
  await assert.rejects(request("GET", "/me", { timeout: 10 }), { name: "ApiError", status: 0, code: "timeout" })
})

test("a caller's abort is passed through, not turned into an ApiError", async () => {
  globalThis.fetch = (_input, init) => new Promise((_resolve, reject) => {
    init?.signal?.addEventListener("abort", () => reject(init.signal?.reason))
  })
  const controller = new AbortController()
  const pending = request("GET", "/me", { signal: controller.signal })
  controller.abort()
  await assert.rejects(pending, { name: "AbortError" })
})
