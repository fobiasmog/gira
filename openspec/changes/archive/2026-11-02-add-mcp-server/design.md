# Design

## Context

- **The token API is fully described.** `docs/openapi.yaml` describes the 37 operations opened to personal API tokens:
  - each has an `operationId` and a summary;
  - each has its path, query and body parameters;
  - `bin/openapi-verify` checks the document against the API.

  35 of the operations answer with JSON; `downloadFile` and `downloadFilePreview` answer with file bytes.
- **The API already enforces every rule.** A Bearer request is authenticated by `ApiTokenAuthentication`:
  - the action must be opened with `allow_token_access`;
  - a read-only token may only send GET and HEAD;
  - project reach comes from `Current#projects`;
  - each token is limited to 300 requests a minute.

  Errors use one envelope, `{ error: { code, message, fields } }` (`Api::BaseController`).
- **The web process is small.** Production runs Puma with 3 threads (`config/puma.rb`).
- **Internal HTTP must look like HTTPS.** `force_ssl` redirects plain HTTP. `X-Forwarded-Proto` is honored only from trusted proxies, which means private networks by default plus `TRUSTED_PROXIES` (`config/environments/production.rb`).
- **Image and entrypoint.** The production image contains Ruby and the bundle but no Node. `bin/docker-entrypoint` runs `db:prepare` only for `./bin/rails server`.
- **The SDK.** The official Ruby SDK, `mcp` 1.8.2, provides:
  - a Streamable HTTP transport that is a Rack application, with `stateless:` and `enable_json_response:` modes and Origin checks;
  - pluggable bearer-token verification that reaches tool handlers as `server_context.auth_info`;
  - input-schema validation of tool arguments;
  - the protocol versions from 2026-07-28 (stateless, no `initialize`) back to 2024-11-05.
- **Decided while exploring:**
  - the server is a thin proxy and a separate instance;
  - it lives in the same repository and is written in Ruby;
  - nginx sends `/mcp` to it.

## Goals / Non-Goals

**Goals:**
- The MCP layer contains no Goalner rules. Whatever a client can do through it, it could do with the same token against `/api`.
- Tools stay in step with the API with no hand-written per-tool code.
- A process boundary that `add-mcp-oauth` can extend without reshaping: a second credential type and a token exchange slot in behind the same verifier and client.

**Non-Goals:**
- Tool-specific behavior, such as composite tools, name lookups or formatting results for models.
- Server-initiated messages: notifications, subscriptions, sampling or elicitation.
- Running the MCP server over stdio for local use. The code would allow it later.

## Decisions

### 1. A separate process from this repository and image

The server is a Rack application in `mcp/`, started by `bin/mcp` from the same Docker image as the web role, as its own Kamal role. It calls the API over HTTP on the private network.

- *Alternative: a Rails route that dispatches tool calls in-process (`Rails.application.call`).* Rejected for three reasons:
  - a nested call goes through the executor middleware again, which resets `Current` and the query cache of the outer request;
  - each MCP request would hold one of the 3 Puma threads while its inner request needs another, so three concurrent tool calls can stall the web process;
  - a bug in the MCP layer would run with full database access.
- *Alternative: a separate repository or service.* Rejected. Tools are generated from `docs/openapi.yaml`, so the server must deploy in lockstep with the API it describes. Shipping both in the same image guarantees that.

### 2. A Rack app that never boots Rails

- **Entry point:** `mcp/config.ru` loads `mcp/lib/goalner_mcp.rb`, which requires the `mcp` gem, `net/http`, `json` and `yaml`. It never requires `config/environment`.
- **Gems:** `mcp` sits in a new Gemfile group `:mcp`. The Rails application requires only `Rails.groups`, so the gem is never loaded there, and the MCP process requires only `Bundler.require(:mcp)`.
- **No database:** the `mcp` role receives no `DATABASE_URL` and no `RAILS_MASTER_KEY`. A test starts the application in a subprocess without them and checks that `Rails` and `ActiveRecord` are not defined.
- **Not autoloaded:** `mcp/` is outside `app/` and `lib/`, so Zeitwerk never loads it.

### 3. Stateless JSON transport from the SDK

The server uses `MCP::Server::Transports::StreamableHTTPTransport` with these options:
- `stateless: true` and `enable_json_response: true`;
- `serve_subscriptions_listen: false`;
- `dns_rebinding_protection` with `allowed_origins` set to the public origin (`MCP_PUBLIC_URL`). Development also allows `localhost` origins, for the MCP Inspector.

What this gives:
- **No session to share.** Any instance answers any request, so no session store or sticky routing is needed.
- **No streaming.** No SSE responses means no long-lived connections through nginx.
- **Protocol versions.** The SDK negotiates versions: 2026-07-28 clients send no `initialize`, and older clients get the handshake answered statelessly. `validate_tool_call_arguments` stays on (spec "Tool arguments").
- *Alternative: hand-written JSON-RPC.* Rejected. The protocol changed three times in 2025–2026, and the SDK tracks it.
- *Alternative: the TypeScript SDK.* Rejected. The runtime image has no Node, and the team works in Ruby.

### 4. Tools generated from `docs/openapi.yaml` at boot

`GoalnerMcp::ToolBuilder` reads the document shipped in the image and builds one `MCP::Tool` per operation.

- **Selection:** operations whose 2xx response has `application/json` content, or no content at all (204). This drops the two file downloads by rule rather than by name.
- **Name, title and description:**
  - the name is the `operationId` (`createTask`), identical to the document so the two can be compared directly;
  - the title is the `summary`;
  - the description is `summary`, then `description`, then one line on the operation's method and path.
- **Input schema:** an object whose properties are:
  - the path parameters (always required);
  - the query parameters;
  - the properties of the JSON request body, required as the body schema says.

  `$ref`, `allOf` and `oneOf` with `null` are inlined from `components`, so each tool schema is self-contained. A property name that appears both as a parameter and in the body makes boot fail. A test checks that today's document has no such collision.
- **Request mapping:**
  - path parameters are substituted with URL encoding (task keys such as `GOAL-12` pass through);
  - query parameters are added only when given;
  - body properties are sent as JSON only when given, and an explicit `null` is sent as `null`. This keeps PATCH semantics ("changes only the fields given").

Alternatives:
- *Hand-written, curated tools.* Rejected. They would duplicate the API's shape in a second place, and the user asked for no logic in the MCP layer.
- *Read the document from `/api/openapi.yaml` at runtime.* Rejected. That route is session-only, and the document in the image already matches the API in the same image.

### 5. Hints by HTTP method

| Method | readOnlyHint | destructiveHint | idempotentHint |
|---|---|---|---|
| GET | true | (not set) | (not set) |
| POST, PATCH | false | false | false |
| PUT | false | false | true |
| DELETE | false | true | true |

`openWorldHint` is `false` everywhere.

- **Explicit false matters:** MCP defaults `destructiveHint` to `true` for non-read-only tools, so it must be set to `false` explicitly.
- **Over-warning is accepted:** some DELETEs are reversible (`removeTaskLabel`, `reopenSubtask`) and are still marked destructive. Clients only ask for confirmation more often.
- *Alternative: an `x-mcp-destructive` extension per operation in the document.* Deferred until the method-based rule proves too coarse.

### 6. Authentication: a verifier that asks the API

A small Rack middleware in front of the transport:

1. **Header check.** It reads `Authorization: Bearer <value>`. A missing header, a value without the `glnr_` prefix, or any other scheme gets 401 with `WWW-Authenticate: Bearer`. Query and body are never read for credentials.
2. **Token check.** It validates the token with `GET /api/me`. A success is cached in-process for 60 seconds, keyed by the SHA-256 of the token, in a bounded LRU of 10,000 entries. A 401 from the API answers the MCP request with 401.
3. **Hand-off.** It stores the verified credential in `env["mcp.auth_info"]` as an `MCP::Server::OAuth::AccessToken`. The SDK passes that to tool handlers as `server_context.auth_info`.

**Revocation during a tool call.** A tool handler that receives 401 from the API raises `GoalnerMcp::Unauthorized`. The middleware turns that into an HTTP 401 for the whole MCP request and drops the cache entry. This covers a token revoked inside the 60-second window (spec scenario "Token revoked between calls").

**Effect on the rate limit.** `GET /api/me` counts toward the token's 300 requests a minute, at most once a minute per token per process.

Alternatives:
- *Check only the format, and let tool calls fail.* Rejected. Anyone with any `glnr_…` string could list tools, and a dead token would succeed on some requests and fail on others.
- *Call `/api/me` on every request with no cache.* Rejected. It doubles the API requests behind each tool call and halves the effective rate limit.

**The seam for `add-mcp-oauth`.** A verifier list keyed by token shape (`glnr_…` here, JWTs later) produces the credential, and `GoalnerMcp::UpstreamCredential.for(auth_info)` turns it into the bearer value sent to the API. In this change that is the token itself. In `add-mcp-oauth` it becomes the exchanged token.

### 7. API client over the private network

`GoalnerMcp::ApiClient` uses `Net::HTTP` with keep-alive to `GOALNER_API_URL`, the web role's private address, never the public URL.

**Headers on every request:**
- `Authorization`;
- `Accept` and `Content-Type: application/json`;
- `X-Forwarded-Proto: https`, so `force_ssl` treats the request as HTTPS. It is trusted because the MCP container sits on a private network;
- `User-Agent: goalner-mcp/<version>`.

No cookies are sent, and no `X-Forwarded-For`, so the API sees the MCP container as the client.

**Timeouts and retries:** 2 seconds to open the connection and 15 seconds to read. Requests are never retried, so a timed-out write is never repeated.

**Unexpected answers:** any 3xx is treated as a misconfiguration. It is logged loudly and returned as the generic tool error, which catches a lost `X-Forwarded-Proto` or a public `GOALNER_API_URL`.

**Tests:** they swap the transport for a Rack adapter that calls `Rails.application` in-process. The suite then runs the real API, with fixtures and token rules, without a network.

### 8. Results and errors

| API outcome | MCP outcome |
|---|---|
| 2xx with JSON | Text content with the response body, unchanged and compact |
| 204 | Text content "Done." |
| 401 | HTTP 401 for the whole request (decision 6) |
| 403, 404, 422, 429 envelope | Tool error: `<code>: <message>`, then one line per field message |
| 3xx, 5xx, timeout, connection error | Tool error: "Goalner is unavailable. Try again later." The detail goes to the log |
| Arguments failing the input schema | Tool error from the SDK naming the arguments; no API request |

- *Alternative: `structuredContent` with an `outputSchema` from the response schema.* Deferred. List operations return arrays, and MCP structured content must be an object, so it would need wrapping that the API doesn't have. Text JSON works with every client.

### 9. Logs and error reports

- **Logs:** one line per request to STDOUT with the request id, the JSON-RPC method, the tool name, the API status (or `-`), the result (`ok`, `tool_error`, `unauthorized`) and the duration. Nothing else is logged: no headers, arguments or bodies.
- **Error reports:** unexpected exceptions go to Sentry when `SENTRY_DSN` is set. The MCP process cannot read the Rails credentials, so the DSN comes from the environment. A scrubber drops request data, headers and the environment, matching `SentryScrubber` in the main application.

### 10. Running it

- **Launcher:** `bin/mcp` runs `puma -C mcp/puma.rb mcp/config.ru`: one process, 16 threads (requests mostly wait on the API), port `MCP_PORT` (default 3100).
- **Development:** `bin/dev` starts it with `GOALNER_API_URL=http://localhost:3000`.
- **Kamal:** `config/deploy.yml` gains an `mcp` role with `cmd: bin/mcp` and the clear env `GOALNER_API_URL` and `MCP_PUBLIC_URL`. `RAILS_MASTER_KEY` moves from the top-level `env.secret` to the `web` role, so the MCP container never receives it.
- **nginx:** the README shows the routing:
  - `location = /mcp` goes to the MCP upstream with buffering off;
  - everything else goes to the web role, as today.
- **Server instructions:** the server sends short instructions to clients:
  - "Goalner is a task tracker; start with `listProjects`";
  - task ids accept keys like `GOAL-12`;
  - a read-only token cannot use tools that change data.

## Risks / Trade-offs

- **[The `mcp` gem moves fast: 1.0 to 1.8 in a few months]** → Pin the exact version. Task 1.2 checks the transport's behavior against the spec scenarios before anything is built on it.
- **[Descriptions written for API readers may be weak prompts for models]** → They are the same text integrators read. Improving a summary in the document improves both.
- **[35 tools is a lot for some clients]** → Measure in practice. A later change can group or filter tools without touching the API.
- **[Prompt injection: task descriptions and comments from other members can steer an assistant holding a read-write token]** → The token's project and access level still bound what can happen, and destructive tools carry hints. The README recommends read-only tokens for assistants that only need to read.
- **[A revoked token can still list tools for up to 60 seconds]** → Tool calls still reach the API, which refuses them at once (decision 6). Listing tools reveals nothing beyond the published document.
- **[Requests with random tokens make the MCP server query `/api/me`]** → A digest lookup is cheap. The README's nginx snippet rate-limits `/mcp` per IP.
- **[Tokens cross the private network in plain HTTP]** → The same holds for nginx to the web role today. The MCP-to-web traffic never leaves the host or private network, and `GOALNER_API_URL` must be private (decision 7 detects a redirect).
- **[One more hop per tool call]** → A keep-alive connection on the private network adds milliseconds against seconds of model generation.

## Migration Plan

1. **Deploy.** Deploy the image with the new `mcp` role. The web role is unchanged apart from where `RAILS_MASTER_KEY` is declared.
2. **Route.** Add the `/mcp` location to nginx and reload it.
3. **Check from outside:**
   - `POST /mcp` without a token answers 401;
   - Claude Code connects with a read-only token and lists the project.

**Rollback:** remove the nginx location and stop the `mcp` role. Nothing else depends on it, and no data was migrated.
