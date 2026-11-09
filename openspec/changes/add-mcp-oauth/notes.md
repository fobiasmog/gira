# Notes

## Task 1.4: JWT verification, metadata and challenge in `bin/mcp` (2026-11-02)

`bin/mcp` with `MCP_PORT=3199`, `MCP_PUBLIC_URL=http://localhost:3199`, `MCP_RESOURCE_URL=https://goalner.com/mcp`, `MCP_ISSUER=https://goalner.com`, and `MCP_JWT_PUBLIC_KEYS` set to the public key of the test credentials' `mcp.jwt_private_key`. The JWTs come from `Oauth::JwtGenerator.generate` under `RAILS_ENV=test`, for user 2 with the scope `read`: one issued now, one issued two hours ago (expired an hour ago, beyond the 30 seconds of leeway). `U=http://localhost:3199`, and every `/mcp` request also sends `Content-Type: application/json`, `Accept: application/json, text/event-stream` and `MCP-Protocol-Version: 2025-11-25`.

### Protected resource metadata, at both well-known paths

```
curl -i $U/.well-known/oauth-protected-resource/mcp

HTTP/1.1 200 OK
content-type: application/json
cache-control: public, max-age=3600
access-control-allow-origin: *

{"resource":"https://goalner.com/mcp","authorization_servers":["https://goalner.com"],"scopes_supported":["read","write"],"bearer_methods_supported":["header"]}
```

`curl -i $U/.well-known/oauth-protected-resource` answers the same.

### No token

```
curl -i -X POST $U/mcp -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'

HTTP/1.1 401 Unauthorized
www-authenticate: Bearer resource_metadata="http://localhost:3199/.well-known/oauth-protected-resource/mcp", scope="read write"
```

The URL is built from `MCP_PUBLIC_URL`; in production it is `https://goalner.com/.well-known/oauth-protected-resource/mcp`, as in the spec scenario "Challenge".

### A JWT from the generator

```
curl -i -X POST $U/mcp -H "Authorization: Bearer $JWT" -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'

HTTP/1.1 200 OK
content-type: application/json

{"jsonrpc":"2.0","id":1,"result":{"tools":[{"name":"showProfile",...},{"name":"listProjects",...},...]}}
```

Listing tools makes no API request (`GOALNER_API_URL` pointed at a closed port).

### An expired JWT

```
curl -i -X POST $U/mcp -H "Authorization: Bearer $EXPIRED_JWT" -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'

HTTP/1.1 401 Unauthorized
www-authenticate: Bearer error="invalid_token", resource_metadata="http://localhost:3199/.well-known/oauth-protected-resource/mcp", scope="read write"
content-type: application/json

{"error":"invalid_token"}
```

### Deviations from the plan

- **Issuer in the main application.** Design decision 11 lists no issuer setting for the main application. The issuer is `https://<mailer.host>` in production (already a required credential, and the application's public origin), `http://localhost:3000` in development and `https://goalner.com` in test (`config/initializers/doorkeeper.rb`). It must equal the MCP role's `MCP_ISSUER`.
- **Development signing key.** Adding `mcp.jwt_private_key` to the development credentials was not possible in this session, so development without that credential generates a key in `tmp/development_mcp_jwt_key.pem`, as Rails does for `secret_key_base`. Test credentials (`config/credentials/test.yml.enc` with its committed key) hold the test key pair.
- **Doorkeeper models.** Doorkeeper uses `Oauth::Application`, `Oauth::AccessToken` and `Oauth::AccessGrant` (its documented custom model classes), so the application can carry the CIMD and DCR helpers.
- **Plain PKCE.** Doorkeeper answers an unsupported challenge method with `invalid_code_challenge_method`; the authorize subclass answers `invalid_request`, as RFC 7636 4.4.1 and the spec scenario "Plain challenge" ask.
- **Connection token scope name.** `ApiToken.connection` would replace Active Record's `connection` class method, so the scope is `ApiToken.of_connections`; `personal` is as designed.
- **Connected at.** Doorkeeper keeps one row per refresh and revokes the replaced row on first use, so `McpConnection` walks back from the oldest live token through rows revoked after their successor appeared. Rows revoked more than 30 days ago are purged (decision 10), so for an older connection the date shown is at most 30 days back.
- **README link on Connected apps.** The frontend policy (`script/check-frontend-policy.mjs`) refuses third-party URLs in client code, so the empty screen links to `/docs/mcp`, which redirects to the README's MCP section on GitHub (`McpGuidesController`).
- **Page tests.** The web-client dependency policy allows exactly `vite`, `@vitejs/plugin-vue`, `typescript` and `vue-tsc` as development dependencies, so there is no Vitest. The page's client and list logic is tested with `node --test` (`app/frontend/api/connections.test.ts`), and the page itself by `test/system/settings_test.rb` and the accessibility test.
- **Kamal.** The repository has no `bin/kamal`; `bundle exec kamal config` was used.

## Task 7.2 and 8.2: the flow against development servers (2026-11-02)

Rails (`bin/rails server -p 3000`) and `bin/mcp` with `MCP_JWT_PUBLIC_KEYS` from `Oauth::JwtGenerator.public_key_pem`, as `bin/dev` starts them, driven by a script (no browser) for a temporary user with two projects, removed afterwards:

| Step | Result |
|---|---|
| `POST /mcp` without a token | 401, `Bearer resource_metadata="http://localhost:3100/.well-known/oauth-protected-resource/mcp", scope="read write"` |
| Protected resource metadata | resource `http://localhost:3100/mcp`, authorization server `http://localhost:3000` |
| Authorization server metadata | as in decision 3, issuer `http://localhost:3000` |
| `POST /oauth/register` | 201, public client, `http://127.0.0.1/callback` |
| Sign-in, then `GET /oauth/authorize` with `redirect_uri=http://127.0.0.1:9999/callback` | consent page "127.0.0.1 wants to access your Goalner account", `form-action 'self' http://127.0.0.1:9999` |
| Approve read-write | 302 to the callback with a code and the state |
| `POST /oauth/token` | 200, `scope=read write`, `expires_in=3600`, a refresh token; JWT `aud=http://localhost:3100/mcp` |
| `tools/list`, `listProjects`, `createTask` in both projects | 35 tools; both projects; both tasks created |
| `GET /api/me/connections`, `DELETE` one | listed with client, host, access and times; 204 |
| Tool call after disconnecting | 401 with `error="invalid_token"` |
| Refresh after disconnecting | 400 `invalid_grant` |
| `GET /oauth/authorize` with Claude Code's client ID (`https://claude.ai/oauth/claude-code-client-metadata`) and `http://localhost:54321/callback` | the document fetched from claude.ai; consent page names "Claude Code", with the loopback warning |

Not covered: Claude Code's and the MCP Inspector's own browser sign-in, which need a person at the browser. The Inspector runs its OAuth flow in the browser at `localhost:6274`; the token and registration endpoints send no CORS headers, so its direct mode may be blocked there.

## claude.ai against a local server (2026-11-03)

claude.ai's connectors call the MCP server from Anthropic's servers, not from the browser: the discovery requests, the token request and every tool call. Only the authorization page opens in the user's browser. So the MCP server and Rails (its metadata, `/oauth/token` and `/oauth/register`) both need public HTTPS URLs, and `localhost` does not work. Claude Code and the MCP Inspector connect from the developer's machine, so they work against `localhost` as it is (tasks 7.2 and 8.2).

**Missing for this to work:** in development the Rails issuer is fixed at `http://localhost:3000` (`config/initializers/doorkeeper.rb`). Behind a tunnel, the authorization server metadata would send claude.ai to `localhost` for the token endpoint, and the issuer would differ from the MCP server's `MCP_ISSUER`. Reading `MCP_ISSUER` in development is enough. Production keeps `https://<mailer.host>`, and test keeps `https://goalner.com`:

```ruby
else
  ENV.fetch("MCP_ISSUER", "http://localhost:3000")
```

Environment variables set everything else:

| Variable | Read by | Value |
|---|---|---|
| `MCP_ISSUER` | the MCP server, and Rails once the change above is in | the Rails tunnel URL |
| `MCP_PUBLIC_URL` | the MCP server, which also takes its allowed host and origin from it | the MCP tunnel URL |
| `MCP_RESOURCE_URL` | both | the MCP tunnel URL with `/mcp` |
| `RAILS_DEVELOPMENT_HOSTS` | Rails host authorization | the Rails tunnel host |
| `MCP_SERVICE_KEY` | both | a random value: the tunnel makes `/internal/mcp_token_exchange` public, and the development default is in the repository |

With cloudflared quick tunnels, which need no account:

```sh
brew install cloudflared
cloudflared tunnel --url http://localhost:3000   # prints https://<a>.trycloudflare.com
cloudflared tunnel --url http://localhost:3100   # prints https://<b>.trycloudflare.com

APP=https://<a>.trycloudflare.com MCP=https://<b>.trycloudflare.com
MCP_ISSUER=$APP MCP_PUBLIC_URL=$MCP MCP_RESOURCE_URL=$MCP/mcp \
RAILS_DEVELOPMENT_HOSTS=${APP#https://} MCP_SERVICE_KEY=$(openssl rand -hex 32) bin/dev
```

Then add a custom connector with the URL `$MCP/mcp` in claude.ai, under Settings → Connectors. Connect opens `$APP/oauth/authorize`. Sign in there, in a session separate from `localhost:5173`'s, and approve.

claude.ai's client ID metadata document (`https://claude.ai/oauth/mcp-oauth-client-metadata`, fetched 2026-11-03):
- Its client ID equals its URL, and its name is "Claude".
- Its one redirect URI is `https://claude.ai/api/mcp/auth_callback`.
- Its `token_endpoint_auth_method` is `none`.

`Oauth::ClientMetadataDocument` accepts it as it is. It also lists the `urn:ietf:params:oauth:grant-type:jwt-bearer` grant type, which has no effect: document grant types are not checked, and Doorkeeper allows only `authorization_code`.

- **Public while the tunnels run.** Only the random URL protects the development app, so use a throwaway account and stop the tunnels afterwards.
- **Quick tunnel URLs change on every restart.** The connector has to be added again each time. A stable URL needs an ngrok static domain or a named Cloudflare tunnel. A single host also needs path routing, as production's nginx does: `/mcp` and `/.well-known/oauth-protected-resource*` go to 3100, and the rest to 3000. `MCP_ISSUER` and `MCP_PUBLIC_URL` then share an origin.
- **`localhost:3100` is refused** while `MCP_PUBLIC_URL` points at the tunnel, by the host check. Local clients use the tunnel URL too.
- **Not yet run against claude.ai.** One assumption is untested: that cloudflared passes the public `Host` and `X-Forwarded-Proto: https`. Rails' host authorization and the sign-in form's origin check depend on them.
