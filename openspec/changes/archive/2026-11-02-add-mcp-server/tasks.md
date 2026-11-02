# Tasks

## 1. Process and transport (risk first)

- [x] 1.1 Add `gem "mcp", "1.8.2"` in a new `group :mcp` of the `Gemfile`, locked in `Gemfile.lock` (design.md, decision 2). Verify:
  - `bin/bundler-audit` passes;
  - `bin/rails runner 'p defined?(MCP)'` prints `nil`, so Rails never loads the gem.
- [x] 1.2 Add `mcp/config.ru`, `mcp/puma.rb`, `mcp/lib/goalner_mcp.rb` and `bin/mcp`. The server has one hard-coded `ping_goalner` tool behind `StreamableHTTPTransport` with `stateless: true`, `enable_json_response: true`, `serve_subscriptions_listen: false` and Origin protection from `MCP_PUBLIC_URL` (decision 3). Verify with curl against `bin/mcp`:
  - a 2026-07-28 `tools/list` (with an `MCP-Protocol-Version` header and no `initialize`) and a 2025-11-25 `initialize` followed by `tools/list` both answer with JSON and no `Mcp-Session-Id` header;
  - `GET /mcp` and `DELETE /mcp` answer 405;
  - a POST with `Origin: https://evil.example` answers 403, and one without `Origin` is processed.

  Record the exact requests and responses in the change's notes. If the SDK's behavior differs from the spec scenarios "MCP endpoint" or "Browser origins", stop and bring the difference back before continuing.
- [x] 1.3 Add `test/mcp/support.rb` with `McpIntegrationTest`. It wraps the MCP Rack app with `Rack::Test` and swaps the API client's transport for a Rack adapter that calls `Rails.application` in-process (decision 7). Also add `test/mcp/process_test.rb`, which starts `mcp/config.ru` in a subprocess with `DATABASE_URL` and `RAILS_MASTER_KEY` unset. Verify:
  - the subprocess answers a `tools/list`;
  - `defined?(Rails)` and `defined?(ActiveRecord)` are false inside it;
  - `bin/rails test test/mcp` runs as part of `bin/rails test`.

## 2. Authentication

- [x] 2.1 Add the authentication middleware and the token verifier (decision 6). The verifier:
  - reads only the `Authorization` header and requires the `glnr_` prefix;
  - validates with `GET /api/me`;
  - caches successes for 60 seconds, keyed by the SHA-256 of the token, in a bounded LRU;
  - stores an `MCP::Server::OAuth::AccessToken` in `env["mcp.auth_info"]`.

  Add `GoalnerMcp::UpstreamCredential.for(auth_info)`, which returns the token itself for now. Verify `test/mcp/authentication_test.rb` covers the spec scenarios "No token" (401 with `WWW-Authenticate: Bearer`, no tools), "Revoked token" and "Token in the query string", using the `api_tokens` fixtures.
- [x] 2.2 Make a tool handler that receives 401 from the API raise `GoalnerMcp::Unauthorized`. The middleware answers that with HTTP 401 and drops the cache entry. Verify the spec scenario "Token revoked between calls": list tools with `glnr_two_goal_read_write`, destroy the fixture token, call `createTask`. The response is 401 and the task count is unchanged.

## 3. Tools

- [x] 3.1 Add `GoalnerMcp::ToolBuilder`, which reads `docs/openapi.yaml` and builds one tool per operation with a JSON or empty 2xx response. It produces names, titles, descriptions and self-contained input schemas, inlining `$ref`, `allOf` and nullable `oneOf`, and fails on parameter/body name collisions (decision 4). Verify `test/mcp/tool_builder_test.rb`:
  - the tool names equal the JSON operations of the document, computed independently in the test from the YAML, so there are 35 tools and no download tools;
  - `createTask` requires `project_id` and `title` and lists the other `TaskCreate` fields as optional;
  - every input schema has no `$ref` left;
  - a fixture document with an added operation yields one more tool, and one with a colliding name fails with a message naming the operation and the property (spec "Document changes").
- [x] 3.2 Set the hints by method (decision 5). Verify the spec scenarios "Read tool" and "Deleting tool" against `tools/list`, including `destructiveHint: false` on `createTask` and `openWorldHint: false` everywhere.
- [x] 3.3 Map tool arguments to requests (decision 4):
  - path parameters URL-encoded;
  - query and body arguments sent only when given;
  - an explicit `null` kept.

  Verify `test/mcp/tool_calls_test.rb` covers the spec scenarios "Partial update", "Explicit null", "Task key as id" and "Missing required argument". The last one makes no API request, which the test checks by counting adapter calls.
- [x] 3.4 Map API outcomes to results and tool errors (decision 8). Verify `test/mcp/tool_calls_test.rb` covers:
  - "Show task": the result's JSON equals the body of `GET /api/projects/:id/tasks/:id`;
  - "No content";
  - "Validation error";
  - "Attribution";
  - "Read-only token writes";
  - "Another project of the owner";
  - "Rate limit": 300 direct `GET /api/projects/:id/board` requests with the token, as in `test/integration/api_token_authentication_test.rb` ("request burst"), then a `createTask` through MCP. The result is the `rate_limited` tool error and the task count is unchanged;
  - "API unavailable": the adapter raises `Errno::ECONNREFUSED` and then answers 302 and 503, and each time the error text contains no host, address or exception class.

## 4. Logs, error reports and running it

- [x] 4.1 Add the request log line and Sentry reporting with the scrubber (decision 9). Verify `test/mcp/logging_test.rb` covers the spec scenario "Logged tool call": a `createTask` with the title "Quarterly plan" and `glnr_two_goal_read_write` is logged with `createTask` and `201`, without the token or the title. Also verify that a raised exception produces a Sentry event without request data or headers, using `Sentry::TestHelper`.
- [x] 4.2 Start the MCP server from `bin/dev` with `GOALNER_API_URL=http://localhost:3000`, and add the `mcp` role to `config/deploy.yml`, moving `RAILS_MASTER_KEY` to the `web` role (decision 10). Verify:
  - Ctrl-C in `bin/dev` stops Puma, Vite and `bin/mcp`;
  - `bin/kamal config` shows the `mcp` role with `cmd: bin/mcp` and without `RAILS_MASTER_KEY`.
- [x] 4.3 Add an "MCP server" section to `README.md` with:
  - what it offers;
  - `claude mcp add --transport http goalner https://goalner.com/mcp --header "Authorization: Bearer ${GOALNER_TOKEN}"`, with a warning not to commit tokens in `.mcp.json`;
  - the advice to use read-only tokens for read-only work;
  - the nginx `location = /mcp` snippet with buffering off and a per-IP rate limit;
  - the environment variables.

  Verify by following the section against `bin/dev`: Claude Code connects to `http://localhost:3100/mcp` with a read-write token created under Settings → API tokens, lists the project and creates a task that then appears on the board.

## 5. Integration

- [x] 5.1 Run `bin/ci` and `bin/openapi-verify`. Verify both pass, and that `bin/rails test` now includes the `test/mcp` files while `test/openapi` stays excluded.
- [x] 5.2 Run the MCP Inspector (`npx @modelcontextprotocol/inspector`) against `bin/dev` with a read-only token. Verify:
  - all 35 tools are listed with their hints;
  - `listProjects`, `showBoard` and `listTasks` succeed;
  - `createTask` returns the `insufficient_scope` tool error.

## Workflow follow-up

- Deploy the `mcp` role and add the nginx route as in design.md, "Migration Plan".
- Archive this change before starting `add-mcp-oauth`'s implementation, so its deltas apply on top of `mcp-server`.
