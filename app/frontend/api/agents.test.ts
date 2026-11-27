import { test, beforeEach } from "node:test"
import assert from "node:assert/strict"
import {
  activeAgents, addableAgents, agentsApi, channelsOf, choiceOf, deletedAgents, mcpCommand, mcpConfig, registerCloneCommand, settingValue, startCommand, withAgent, worksOn,
} from "./agents.ts"
import type { ProjectAgent, UserCard, VisibleAgent } from "./types.ts"

interface Call { url: string; init: RequestInit }
let calls: Call[]

function respond(status: number, body?: unknown) {
  globalThis.fetch = async (input, init = {}) => {
    calls.push({ url: String(input), init })
    return new Response(body === undefined ? null : JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } })
  }
}

const bob: UserCard = { id: 2, name: "Bob", email_address: "bob@example.com", avatar_url: null, agent: false, deleted: false }
const agent = (id: number, name: string, extra: Partial<ProjectAgent> = {}): ProjectAgent => ({
  id, name, email_address: `calm-owl-000${id}@agents.goalner.com`, avatar_url: null, agent: true, deleted: false,
  created_by: bob, created_at: "2026-11-01T10:00:00Z", deleted_at: null, model: null, instructions: null, token_count: 1, removable: false,
  checked_in_at: null, online: false, working_on: null, lease: null, ...extra,
})
const fish = agent(7, "Fish")
const owl = agent(8, "Owl", { deleted: true, deleted_at: "2026-11-10T10:00:00Z", token_count: 0 })

const body = (call: Call) => JSON.parse(String(call.init.body)) as unknown

beforeEach(() => {
  calls = []
  Object.assign(globalThis, {
    document: { querySelector: () => ({ content: "csrf-123" }) },
    location: { href: "http://example.test/app/projects/1/agents", assign: () => {} },
  })
})

test("lists a project's agents and the agents the user can see", async () => {
  respond(200, [fish, owl])
  assert.deepEqual(await agentsApi.inProject(1), [fish, owl])
  assert.equal(calls[0]!.url, "/api/projects/1/agents")

  respond(200, [])
  await agentsApi.visible()
  assert.equal(calls[1]!.url, "/api/agents")
})

test("creates an agent with its settings, and no token or password", async () => {
  respond(201, fish)

  await agentsApi.create(1, { name: "Fish", model: "opus", instructions: null })

  assert.equal(calls[0]!.url, "/api/projects/1/agents")
  assert.equal(calls[0]!.init.method, "POST")
  assert.equal((calls[0]!.init.headers as Record<string, string>)["X-CSRF-Token"], "csrf-123")
  assert.deepEqual(body(calls[0]!), { name: "Fish", model: "opus", instructions: null })
})

test("edits an agent's settings, and an empty setting is sent as null", async () => {
  respond(200, fish)

  await agentsApi.update(7, { name: "Fish", model: settingValue(""), instructions: settingValue("Keep commits small.") })

  assert.equal(calls[0]!.url, "/api/agents/7")
  assert.equal(calls[0]!.init.method, "PATCH")
  assert.deepEqual(body(calls[0]!), { name: "Fish", model: null, instructions: "Keep commits small." })
  assert.equal(settingValue("  "), null)
})

test("the start command names the agent, quoted for the shell, or gives its id when the name is shared or made of digits", () => {
  const reviewer = agent(9, "Code Reviewer")
  assert.equal(startCommand(fish, [fish, reviewer]), "bin/goalner-worker Fish")
  assert.equal(startCommand(reviewer, [fish, reviewer]), "bin/goalner-worker 'Code Reviewer'")
  assert.equal(startCommand(agent(10, "Bob's bot"), []), `bin/goalner-worker 'Bob'\\''s bot'`)
  assert.equal(startCommand(fish, [fish, agent(11, "fish")]), "bin/goalner-worker 7")
  assert.equal(startCommand(agent(12, "42"), []), "bin/goalner-worker 12")
  assert.equal(registerCloneCommand("SCH"), "bin/goalner-worker register --clone SCH=<path to the clone>")
})

test("issues and revokes a token", async () => {
  respond(201, { token: "glnr_x" })
  await agentsApi.issueToken(7, { name: "runner", access: "read", channels: ["mcp"] }, "secret")
  assert.equal(calls[0]!.url, "/api/agents/7/tokens")
  assert.deepEqual(body(calls[0]!), { name: "runner", access: "read", channels: ["mcp"], current_password: "secret" })

  respond(204)
  await agentsApi.revokeToken(7, 31)
  assert.equal(calls[1]!.url, "/api/agents/7/tokens/31")
  assert.equal(calls[1]!.init.method, "DELETE")
})

test("handles an agent by its account's id", async () => {
  respond(200, fish)
  await agentsApi.update(7, { name: "Scout" })
  await agentsApi.restore(7)
  await agentsApi.addToProject(2, 7)
  respond(204)
  await agentsApi.delete(7)
  await agentsApi.removeFromProject(1, 7)

  assert.deepEqual(calls.map((call) => `${call.init.method} ${call.url}`), [
    "PATCH /api/agents/7", "POST /api/agents/7/restoration", "POST /api/projects/2/agent_memberships",
    "DELETE /api/agents/7", "DELETE /api/projects/1/members/7",
  ])
  assert.deepEqual(body(calls[0]!), { name: "Scout" })
  assert.deepEqual(body(calls[2]!), { agent_id: 7 })
})

test("the channel choice maps to the channels a token is issued for, and back", () => {
  assert.deepEqual(channelsOf("api"), ["api"])
  assert.deepEqual(channelsOf("mcp"), ["mcp"])
  assert.deepEqual(channelsOf("both"), ["api", "mcp"])
  assert.equal(choiceOf(["mcp", "api"]), "both")
  assert.equal(choiceOf(["mcp"]), "mcp")
  assert.equal(choiceOf(["api"]), "api")
  assert.ok(worksOn({ channels: ["api", "mcp"] }, "mcp"))
  assert.ok(!worksOn({ channels: ["api"] }, "mcp"))
})

test("a project's agents split into active and deleted", () => {
  assert.deepEqual(activeAgents([fish, owl]), [fish])
  assert.deepEqual(deletedAgents([fish, owl]), [owl])
})

test("agents not yet in the project can be added to it", () => {
  const visible = (id: number, projectIds: number[]): VisibleAgent => ({
    ...agent(id, `Agent ${id}`), projects: projectIds.map((projectId) => ({ id: projectId, title: `P${projectId}`, short_name: `P${projectId}` })),
  })
  const [here, elsewhere, both] = [visible(1, [1]), visible(2, [2]), visible(3, [1, 2])]

  assert.deepEqual(addableAgents([here, elsewhere, both], 1), [elsewhere])
  assert.deepEqual(addableAgents([here, elsewhere, both], 3), [here, elsewhere, both])
})

test("an agent joins the list by name, or replaces its entry", () => {
  const newt = agent(9, "Newt")

  assert.deepEqual(withAgent([fish, owl], newt).map((entry) => entry.name), ["Fish", "Newt", "Owl"])
  assert.deepEqual(withAgent([fish, owl], { ...owl, name: "Albatross" }).map((entry) => entry.name), ["Albatross", "Fish"])
})

test("the MCP configuration names the endpoint the server gave, whatever the page's origin, and carries the token", () => {
  assert.equal(
    mcpCommand("http://localhost:3100/mcp", "glnr_secret"),
    'claude mcp add --transport http goalner http://localhost:3100/mcp --header "Authorization: Bearer glnr_secret"',
  )
  assert.deepEqual(JSON.parse(mcpConfig("https://goalner.com/mcp", "glnr_secret")), {
    mcpServers: { goalner: { type: "http", url: "https://goalner.com/mcp", headers: { Authorization: "Bearer glnr_secret" } } },
  })
})
