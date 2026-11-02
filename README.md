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

AI assistants such as Claude Code and Cursor can work with Goalner through the
Model Context Protocol at `https://goalner.com/mcp`. The MCP server offers the
token API as tools, one per JSON operation of `docs/openapi.yaml` (35 of them;
file downloads are left out), named by their `operationId`: `listProjects`,
`showBoard`, `createTask` and so on. Read tools are marked read-only and
deleting tools destructive, so clients can ask before using them.

It authenticates with a personal API token and acts exactly as that token
would against `/api`: the same project, access level, endpoints, rate limit
and attribution. Each tool call is one API request.

Connect Claude Code with a token from **Settings → API tokens**:

```sh
export GOALNER_TOKEN=glnr_...
claude mcp add --transport http goalner https://goalner.com/mcp --header "Authorization: Bearer ${GOALNER_TOKEN}"
```

The shell puts the token itself into the configuration. That is fine in the
default `local` scope (`~/.claude.json`), but **never commit a token**: with
`--scope project` the header lands in `.mcp.json`. There, single-quote the
header (`'Authorization: Bearer ${GOALNER_TOKEN}'`) so the file keeps the
variable, which Claude Code expands at startup.

Give an assistant a **read-only token** when it only needs to read. Task
descriptions and comments written by other members reach the assistant too,
and a read-only token bounds what any instruction hidden in them can do: tools
that change data then answer with the `insufficient_scope` error.

In development, `bin/dev` starts the MCP server at `http://localhost:3100/mcp`
next to Rails and Vite:

```sh
claude mcp add --transport http goalner-dev http://localhost:3100/mcp --header "Authorization: Bearer glnr_..."
npx @modelcontextprotocol/inspector   # or try it in the MCP Inspector (Streamable HTTP, same header)
```

### Running it

The MCP server is a separate process from the same image, started by `bin/mcp`
(the `mcp` role in `config/deploy.yml`). It never boots Rails and has no
database credentials: it reaches Goalner only through the API, over the
private network. Its environment:

| Variable | Meaning |
|---|---|
| `GOALNER_API_URL` | The web role's private address, never the public URL (development: `http://localhost:3000`). Requests carry `X-Forwarded-Proto: https`, so the web role must see the MCP container as a trusted proxy (private networks are). |
| `MCP_PUBLIC_URL` | The public origin, `https://goalner.com` (development: `http://localhost:3100`). Requests with another `Host`, or from a browser page on another origin, are refused with 403. |
| `MCP_PORT` | The port to listen on, 3100 by default. |
| `SENTRY_DSN` | Optional. Unexpected errors are reported there, without request data, headers or arguments. |

`GOALNER_API_URL` and `MCP_PUBLIC_URL` are required in production. The log has
one line per request with the method, tool, API status, result and duration,
and never tokens, arguments or results.

nginx sends `/mcp` to the MCP server and everything else to the web role, as
before. Keep the original `Host`, turn buffering off, and limit requests per IP
(random tokens make the MCP server ask the API):

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
```

Для дат всегда юзать ```.current``` ибо он возвращает с учётом ```Time.zone```


Дамп с базы
```pg_dump -O -U deadline -b -Ft -c --if-exists  > deadline.tar```
