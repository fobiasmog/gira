# README

## Development

Prerequisites: Ruby (see `.ruby-version`), Node 22.18 or newer, PostgreSQL 18 and libvips.

libvips is required even for a bare start: every new user gets a generated
default avatar. Without it, creating a user fails with the misleading
`uninitialized constant Vips::Image` (Active Storage swallows the real "could
not open library 'vips'" error). On macOS:

```sh
brew install vips
```

Setup:

```sh
bundle install
npm ci
bin/rails db:prepare
```

Development has no mail delivery, so sign-up confirmation emails never arrive.
Create a confirmed user from the command line instead (passwords need at least
12 characters):

```sh
bin/rails runner 'User.find_or_create_by!(email_address: "you@example.com") { |u| u.name = "Your Name"; u.password = "your long password"; u.confirmed_at = Time.current }'
```

Run the servers in two terminals with `make backend` (Rails on port 3000) and
`make frontend` (Vite on port 5173), or both at once with `bin/dev`. Then open
http://localhost:5173 and sign in. Vite passes every path outside `/vite/` on
to Rails, so the whole app runs on one origin, which the SVG icon sprite needs
(browsers refuse a sprite from another origin, whatever its CORS headers).
Opening `/app` on port 3000 redirects to the same path on port 5173.

## API tokens

Scripts and integrations call the JSON API under `/api` with a personal API
token. Create one in the app under **Settings → API tokens**. A token:

- belongs to you and acts as you: tasks and comments it creates are yours;
- reaches one project you are a member of, and no other;
- is read-only (GET and HEAD only) or read-write;
- expires after 7, 30, 90 or 365 days (the API accepts 1 to 365);
- is shown once, when it is created. Only a digest is stored, so a lost token
  cannot be recovered: revoke it and create a new one.

Tokens are revoked when you revoke them, change or reset your password, leave
or are removed from the project, or the project is archived. A revoked token
never works again, even if you rejoin the project.

Send the token in the `Authorization` header. A request with this header is
authenticated by the token alone, needs no CSRF token, and ignores cookies.
Tokens in the URL or the request body are not accepted.

```sh
curl -H "Authorization: Bearer glnr_..." http://localhost:3000/api/projects
```

Endpoints available to tokens, all under `/api`:

- `GET /me`; `GET /projects` (only the token's project); `GET /projects/:id`;
  `GET /projects/:id/board`; `GET /projects/:id/statuses` (the board's
  columns); `GET /projects/:id/members`;
- tasks: `/projects/:id/tasks` (list, show, create, update, archive with
  DELETE), and per task `placement`, `subtasks`, `completion`, `label`, `sprint`
  and `comments`; `PATCH`/`DELETE /comments/:id` for your own comments;
- labels, milestones (with `recovery`), and sprints (with `activation`,
  `archival` and `tasks`) under `/projects/:id`;
- downloads of attachments and avatars from the `/files/...` URLs in responses.

Everything else (projects, members, invitations, changing columns, your
account, tokens, teammates, statistics, announcements and feedback) answers a
token with 403.

The full reference, with every parameter, body and response, is at
**`/api/docs`** (for example http://localhost:3000/api/docs) for signed-in
users, with "Try it out" for requests authorized by a token you paste in. The
same OpenAPI 3.1 document, `docs/openapi.yaml`, downloads from
`/api/openapi.yaml` for Postman, Insomnia or a client generator.

Errors use the API's JSON envelope, `{ "error": { "code", "message" } }`:

| Status | Code | Meaning |
|---|---|---|
| 401 | `invalid_token` | The token is unknown, expired or revoked. |
| 403 | `token_not_allowed` | The endpoint is not available to tokens. |
| 403 | `insufficient_scope` | A read-only token tried to change something. |
| 404 | `not_found` | The record does not exist or is outside the token's project. |
| 429 | `rate_limited` | More than 300 requests in a minute with this token. |

Create a task in the first column (use your project's id):

```sh
curl -X POST http://localhost:3000/api/projects/1/tasks \
  -H "Authorization: Bearer glnr_..." \
  -H "Content-Type: application/json" \
  -d '{"title": "Fix the flaky build"}'
```

### Verifying the API document

`docs/openapi.yaml` is written by hand. After changing it, a serializer, or an
action opened with `allow_token_access`, check it against the API:

```sh
bin/openapi-verify
```

It runs the contract tests in `test/openapi/` (they end in `_contract.rb`, so
`bin/rails test` and CI skip them). It needs no server and no network, takes a
few seconds, and exits non-zero naming each mismatch, so it also works as a
git `pre-push` hook.

## MCP server

AI assistants such as Claude can work with Goalner through the Model Context
Protocol at `https://goalner.com/mcp`. The MCP server offers the token API as
tools, one per JSON operation of `docs/openapi.yaml` (35 of them; file
downloads are left out), named by their `operationId`: `listProjects`,
`showBoard`, `createTask` and so on. Read tools are marked read-only and
deleting tools destructive, so clients can ask before using them.

A client connects in one of two ways:

- **Sign in (OAuth).** The client sends you to Goalner to sign in and approve
  it. The connection reaches **all of your projects**, including ones you join
  later, read-only or read-write as you choose. This is how claude.ai, Claude
  Desktop and mobile, and Claude Code connect.
- **A personal API token** in the `Authorization` header, for one project, as
  below. Clients that cannot sign in use this.

Either way the server acts exactly as a token would against `/api`: the same
reach, access level, endpoints, rate limit and attribution. Each tool call is
one API request.

### claude.ai

In claude.ai, open **Settings → Connectors → Add custom connector**, name it
Goalner and enter `https://goalner.com/mcp`, with no OAuth client ID or
secret. Choose **Connect**: Goalner asks you to sign in if needed, then shows
the consent page. It names the app and, more prominently, where it will send
you back (`claude.ai`). Keep **Read only** unless the assistant should
create and change tasks, then **Approve**. The connector then works in Claude
Desktop and mobile too.

### Claude Code

```sh
claude mcp add --transport http goalner https://goalner.com/mcp
```

Then run `/mcp` in Claude Code and choose **Authenticate**: your browser opens
Goalner's consent page. Claude Code receives the code on `localhost`, so the
page warns that only an app on this device will get access.

Give an assistant **read-only access** when it only needs to read. Task
descriptions and comments written by other members reach the assistant too,
and read-only access bounds what any instruction hidden in them can do: a
read-only connection does not even list the tools that change data.

### With a personal API token

Clients that cannot sign in send a token from **Settings → API tokens**:

```sh
export GOALNER_TOKEN=glnr_...
claude mcp add --transport http goalner https://goalner.com/mcp --header "Authorization: Bearer ${GOALNER_TOKEN}"
```

The shell puts the token itself into the configuration. That is fine in the
default `local` scope (`~/.claude.json`), but **never commit a token**: with
`--scope project` the header lands in `.mcp.json`. There, single-quote the
header (`'Authorization: Bearer ${GOALNER_TOKEN}'`) so the file keeps the
variable, which Claude Code expands at startup. A read-only token makes tools
that change data answer with the `insufficient_scope` error.

### Connected apps

**Settings → Connected apps** lists every app you connected by signing in:
its name, where it redirects, its access, when it connected and when it was
last active. **Disconnect** ends a connection at once: its next tool call
answers 401 and its refresh fails, so it has to ask you again. A connection
also ends when you change or reset your password, and after 90 days unused.
Leaving a project only takes that project out of its reach.

### Development

`bin/dev` starts the MCP server at `http://localhost:3100/mcp` next to Rails
and Vite. Rails is the authorization server at `http://localhost:3000`, and
`bin/dev` hands the MCP server the public key that verifies its access tokens
(without `mcp.jwt_private_key` in the development credentials, Rails keeps a
key in `tmp/development_mcp_jwt_key.pem`).

```sh
claude mcp add --transport http goalner-dev http://localhost:3100/mcp   # then /mcp → Authenticate
claude mcp add --transport http goalner-dev http://localhost:3100/mcp --header "Authorization: Bearer glnr_..."
npx @modelcontextprotocol/inspector   # or try it in the MCP Inspector (Streamable HTTP)
```

### How sign-in works

Goalner is an OAuth 2.1 authorization server (Doorkeeper), and the MCP server
a resource server:

1. A request to `/mcp` without a token gets 401 with
   `WWW-Authenticate: Bearer scope="read write", resource_metadata="https://goalner.com/.well-known/oauth-protected-resource/mcp"`.
2. The client reads that metadata, then `https://goalner.com/.well-known/oauth-authorization-server`.
3. It registers at `/oauth/register` (dynamic client registration). Client ID
   metadata documents, client IDs that are HTTPS URLs Goalner would fetch,
   are paused: the metadata does not offer them, and such a client ID gets an
   error page (`config.x.oauth.client_metadata_documents`).
   Redirect URIs use HTTPS, or HTTP on `localhost` or an IPv4 loopback
   address such as `127.0.0.1`, on any port. IPv6 loopback addresses such as
   `[::1]` are not supported: the consent page's Content Security Policy
   cannot name them, so the browser would block the redirect, and
   registration refuses them.
4. It sends you to `/oauth/authorize` with an S256 PKCE challenge; you
   approve, and it exchanges the code at `/oauth/token`.
5. Access tokens are JWTs signed with ES256, valid for an hour, for
   `https://goalner.com/mcp` only: `/api` refuses them. Refresh tokens
   rotate: the one a refresh replaced stops working once the new access token
   reaches the MCP server, with any request, or the new refresh token is used.
6. The first time the MCP server sees an access token, whatever the request,
   it exchanges it for a short-lived connection token at
   `/internal/mcp_token_exchange`, with its service key. Tool calls then call `/api`
   with that. It caches connection tokens in Redis, encrypted with a key
   derived from the access token. If the exchange cannot be reached, or
   refuses the service key, the client gets 503 and keeps its tokens.

### Running it

The MCP server is a separate process from the same image, started by `bin/mcp`
(the `mcp` role in `config/deploy.yml`). It never boots Rails and has no
database credentials: it reaches Goalner only through the API, over the
private network. Its environment:

| Variable | Meaning |
|---|---|
| `GOALNER_API_URL` | The web role's private address, never the public URL (development: `http://localhost:3000`). Requests carry `X-Forwarded-Proto: https`, so the web role must see the MCP container as a trusted proxy (private networks are). |
| `MCP_PUBLIC_URL` | The public origin, `https://goalner.com` (development: `http://localhost:3100`). Requests with another `Host`, or from a browser page on another origin, are refused with 403. |
| `MCP_RESOURCE_URL` | The MCP endpoint, `https://goalner.com/mcp`: the audience of access tokens (development: `http://localhost:3100/mcp`). |
| `MCP_ISSUER` | Goalner's origin, `https://goalner.com`, as its authorization server metadata names it (development: `http://localhost:3000`). The web role reads it too, as the issuer of the tokens it signs. |
| `MCP_JWT_PUBLIC_KEYS` | The PEM public key of the web role's `mcp.jwt_private_key`; several keys, one after another, while rotating. |
| `MCP_SERVICE_KEY` | Secret. The key for the connection token exchange, the same as the web role's. |
| `REDIS_URL` | Secret. The connection token cache, the Valkey accessory: `redis://:<password>@goalner-redis:6379/0`. Without it outside production, an in-memory cache is used. |
| `MCP_PORT` | The port to listen on, 3100 by default. |
| `SENTRY_DSN` | Optional. Unexpected errors are reported there, without request data, headers or arguments. |

All but `MCP_PORT` and `SENTRY_DSN` are required in production: the process
refuses to start without them. The web role needs `MCP_SERVICE_KEY`,
`MCP_RESOURCE_URL` and `MCP_ISSUER` in its environment, and refuses to boot
without them, and `mcp.jwt_private_key` in its credentials
(`config/credentials.example.yml`). `config/deploy.yml` defines `MCP_ISSUER`
and `MCP_RESOURCE_URL` once, in the top-level `env`, so both roles read the
same values. The log has one line per
request with the method, tool, API status, result and duration, and never
tokens, arguments or results.

Deploy in this order: the web role (migrations, new secrets), then the Valkey
accessory (`bundle exec kamal accessory boot redis`), then the mcp role, then nginx.

nginx sends `/mcp` and the protected resource metadata to the MCP server,
refuses `/internal/` from outside, and sends everything else to the web role,
as before. Keep the original `Host`, turn buffering off, and limit requests
per IP (random tokens make the MCP server ask the API):

```nginx
# In the http block.
limit_req_zone $binary_remote_addr zone=mcp:10m rate=10r/s;

# In the server block of goalner.com.
location = /mcp {
    limit_req zone=mcp burst=40 nodelay;
    proxy_pass http://127.0.0.1:3100;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Request-Id $request_id;
    proxy_buffering off;
}

location = /.well-known/oauth-protected-resource {
    proxy_pass http://127.0.0.1:3100;
    proxy_set_header Host $host;
}

location ^~ /.well-known/oauth-protected-resource/ {
    proxy_pass http://127.0.0.1:3100;
    proxy_set_header Host $host;
}

# The connection token exchange is for the MCP server alone, which reaches
# the web role over the private network.
location ^~ /internal/ {
    return 404;
}
```

To roll back sign-in, remove the two protected resource locations: clients
then get a 401 without a metadata pointer, and personal tokens keep working.

### Rotating keys

The signing key:

1. Generate a key (`config/credentials.example.yml` has the command) and add
   its public key after the current one in `MCP_JWT_PUBLIC_KEYS`. Deploy the
   mcp role.
2. Put the new private key into `mcp.jwt_private_key` and deploy the web role.
3. After an hour, when every token signed by the old key has expired, remove
   the old public key and deploy the mcp role.

No client has to refresh or sign in again: the exchange recognizes Goalner's
own tokens by their stored digest, whichever key signed them.

The service key: set a new `MCP_SERVICE_KEY` and redeploy both roles. Until
both run with the same key, requests with an access token the MCP server has
not exchanged yet get 503 "Goalner is unavailable". Clients keep their tokens
and stay signed in; personal tokens are not affected.

Для дат всегда юзать ```.current``` ибо он возвращает с учётом ```Time.zone```


Дамп с базы
```pg_dump -O -U deadline -b -Ft -c --if-exists  > deadline.tar```
