# Notes

## Task 1.2: transport behavior of `mcp` 1.8.2 (2026-10-30)

`bin/mcp` in development (`MCP_PUBLIC_URL` unset, so `http://localhost:3100`), one `ping_goalner` tool, transport options `stateless: true`, `enable_json_response: true`, `serve_subscriptions_listen: false`, `allowed_hosts: ["localhost"]`, `allowed_origins: ["http://localhost:3100"]` plus the Inspector origins. `U=http://localhost:3100/mcp`.

### 2026-07-28 `tools/list` without `initialize`

```
curl -i -X POST $U -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/list' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"curl","version":"1"},"io.modelcontextprotocol/clientCapabilities":{}}}}'

HTTP/1.1 200 OK
content-type: application/json

{"jsonrpc":"2.0","id":1,"result":{"ttlMs":0,"cacheScope":"private","tools":[{"name":"ping_goalner",...}],"resultType":"complete"}}
```

No `Mcp-Session-Id`. The modern path requires both `application/json` and `text/event-stream` in `Accept`, and an `Mcp-Method` header matching the body; it still answers with plain JSON when the handler sends no notifications.

### 2025-11-25 `initialize`, then `tools/list`

```
curl -i -X POST $U -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"curl","version":"1"}}}'

HTTP/1.1 200 OK
content-type: application/json

{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{...},"serverInfo":{"name":"goalner","title":"Goalner","version":"1"},"instructions":"..."}}

curl -i -X POST $U -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-11-25' -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

HTTP/1.1 200 OK
content-type: application/json

{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"ping_goalner",...}]}}
```

Neither response carries `Mcp-Session-Id`.

### GET and DELETE

```
curl -i $U -H 'Accept: text/event-stream'
HTTP/1.1 405 Method Not Allowed
{"jsonrpc":"2.0","error":{"code":-32600,"message":"Method not allowed"}}

curl -i -X DELETE $U -H 'MCP-Protocol-Version: 2025-11-25'
HTTP/1.1 200 OK
{"success":true}

curl -i -X DELETE $U
HTTP/1.1 200 OK

curl -i -X DELETE $U -H 'MCP-Protocol-Version: 2026-07-28'
HTTP/1.1 405 Method Not Allowed
```

**Differs from the spec** ("MCP endpoint": GET and DELETE answer 405). In stateless mode the SDK answers a legacy `DELETE` with 200 and `{"success":true}`; only a `DELETE` with the 2026-07-28 header gets 405.

**Resolved** (decided 2026-10-30): `GoalnerMcp.app` passes only POST to the transport and answers every other method with 405 and `Allow: POST`. The spec stays as written.

```
curl -i -X DELETE $U -H 'MCP-Protocol-Version: 2025-11-25'
HTTP/1.1 405 Method Not Allowed
allow: POST
```

### Origins and hosts

```
curl -i -X POST $U -H 'Origin: https://evil.example' -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-11-25' -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"ping_goalner","arguments":{}}}'
HTTP/1.1 403 Forbidden
{"jsonrpc":"2.0","error":{"code":-32600,"message":"Forbidden: Invalid Origin header"}}

(same request without Origin)
HTTP/1.1 200 OK
{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"pong"}],"isError":false}}

(Origin: http://localhost:6274, the Inspector, in development)
HTTP/1.1 200 OK

(Host: evil.example)
HTTP/1.1 403 Forbidden
{"jsonrpc":"2.0","error":{"code":-32600,"message":"Forbidden: Invalid Host header"}}
```

Matches "Browser origins". The SDK also checks `Host` against the loopback names plus `allowed_hosts`, so nginx must pass the public host (`proxy_set_header Host $host;`), or every request is refused with 403.

### Other observations

- `allowed_origins` takes exact values only, so development lists the Inspector's default origins rather than any `localhost` port.
- `MCP::Tool::Annotations` defaults to `destructiveHint: true`, `idempotentHint: false` and `openWorldHint: true`; a hint left "not set" (decision 5) must be passed as `nil`.
- An exception raised in a tool handler becomes a JSON-RPC error inside the SDK and never reaches Rack middleware, so `GoalnerMcp::Unauthorized` (task 2.2) has to be signalled to the middleware out of band.

## Task 4.3: the README against `bin/dev` (2026-10-30)

Rails on port 3000 and `bin/mcp` on 3100 with `GOALNER_API_URL=http://localhost:3000`, in the sandbox's development database. The read-write token was issued with `ApiToken.issue` in `bin/rails runner`, since no browser was available for Settings → API tokens.

- `claude mcp add --transport http goalner-dev http://localhost:3100/mcp --header "Authorization: Bearer ${GOALNER_TOKEN}"`, then `claude mcp list`: `goalner-dev: http://localhost:3100/mcp (HTTP) - ✔ Connected`.
- `claude -p` with only `listProjects` and `createTask` allowed: it listed project 1 (Demo, DEMO) and created DEMO-2, "Created by Claude Code over MCP". `GET /api/projects/1/board` shows DEMO-2 in the first column; its creator is the token's owner.
- The MCP log for those calls (Claude Code uses the 2026-07-28 lifecycle):

```
mcp request_id=… method=server/discover tool=- api_status=- result=ok duration_ms=61.3
mcp request_id=… method=tools/list tool=- api_status=- result=ok duration_ms=0.4
mcp request_id=… method=tools/call tool=listProjects api_status=200 result=ok duration_ms=63.7
mcp request_id=… method=tools/call tool=createTask api_status=201 result=ok duration_ms=68.3
```

The token appears nowhere in the log.

## Task 5.2: MCP Inspector (2026-10-30)

`npx @modelcontextprotocol/inspector` 2.13.0 in `--cli` mode (no browser in the sandbox) against the same servers, with a read-only token:

- `--method tools/list --strict`: 35 tools, each with `readOnlyHint` and `openWorldHint: false`; 15 read-only; destructive: `archiveTask`, `removeTaskLabel`, `reopenSubtask`, `deleteComment`, `deleteMilestone`. `--strict` reports 0 errors and 11 portability warnings, all for nullable properties written as `type: [integer, "null"]` in `docs/openapi.yaml` (`anyOf` would suit single-`type` dialects such as Gemini's).
- `listProjects`, `showBoard project_id=1` and `listTasks project_id=1` succeed.
- `createTask project_id=1 title=Inspector` returns the tool error `insufficient_scope: This API token is read-only.`
