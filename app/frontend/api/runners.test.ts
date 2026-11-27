import { test, beforeEach } from "node:test"
import assert from "node:assert/strict"
import { registerCommand, runnersApi } from "./runners.ts"

interface Call { url: string; init: RequestInit }
let calls: Call[]

function respond(status: number, body?: unknown) {
  globalThis.fetch = async (input, init = {}) => {
    calls.push({ url: String(input), init })
    return new Response(body === undefined ? null : JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } })
  }
}

const body = (call: Call) => JSON.parse(String(call.init.body)) as unknown

beforeEach(() => {
  calls = []
  Object.assign(globalThis, {
    document: { querySelector: () => ({ content: "csrf-123" }) },
    location: { href: "http://example.test/app/settings/runners", assign: () => {} },
  })
})

test("lists, creates, rotates and revokes runners, with the current password where a secret is issued", async () => {
  respond(200, [])
  await runnersApi.list()
  respond(201, { secret: "glnr_runner_x" })
  await runnersApi.create("laptop", "pw")
  await runnersApi.rotate(3, "pw")
  respond(204)
  await runnersApi.revoke(3)

  assert.deepEqual(calls.map((call) => `${call.init.method ?? "GET"} ${call.url}`), [
    "GET /api/me/runners", "POST /api/me/runners", "POST /api/me/runners/3/secret_rotation", "DELETE /api/me/runners/3",
  ])
  assert.deepEqual(body(calls[1]!), { name: "laptop", current_password: "pw" })
  assert.deepEqual(body(calls[2]!), { current_password: "pw" })
})

test("the register command names this Goalner and the secret", () => {
  assert.equal(registerCommand("http://localhost:3000", "glnr_runner_abc"), "bin/goalner-worker register --url http://localhost:3000 --token glnr_runner_abc")
})
