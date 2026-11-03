import { test, beforeEach } from "node:test"
import assert from "node:assert/strict"
import { connectionsApi, withoutConnection } from "./connections.ts"
import type { Connection } from "./types.ts"

interface Call { url: string; init: RequestInit }
let calls: Call[]

function respond(status: number, body?: unknown) {
  globalThis.fetch = async (input, init = {}) => {
    calls.push({ url: String(input), init })
    return new Response(body === undefined ? null : JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } })
  }
}

const claude: Connection = {
  id: 3, client_name: "Claude", redirect_host: "claude.ai", access: "read_write",
  connected_at: "2026-10-01T10:00:00Z", last_active_at: "2026-11-02T09:30:00Z",
}

beforeEach(() => {
  calls = []
  Object.assign(globalThis, {
    document: { querySelector: () => ({ content: "csrf-123" }) },
    location: { href: "http://example.test/app/settings/connected-apps", assign: () => {} },
  })
})

test("lists the connections of the signed-in user", async () => {
  respond(200, [claude])

  assert.deepEqual(await connectionsApi.list(), [claude])
  assert.equal(calls[0]!.url, "/api/me/connections")
  assert.equal(calls[0]!.init.method ?? "GET", "GET")
})

test("disconnects one, with the CSRF token", async () => {
  respond(204)

  await connectionsApi.disconnect(3)
  assert.equal(calls[0]!.url, "/api/me/connections/3")
  assert.equal(calls[0]!.init.method, "DELETE")
  assert.equal((calls[0]!.init.headers as Record<string, string>)["X-CSRF-Token"], "csrf-123")
})

test("a disconnected connection leaves the list", () => {
  const other = { ...claude, id: 4, client_name: "Claude Code" }

  assert.deepEqual(withoutConnection([claude, other], 3), [other])
  assert.deepEqual(withoutConnection([other], 3), [other])
})
