# README

## Development

Prerequisites: Ruby (see `.ruby-version`), Node 22.18 or newer, PostgreSQL 18,
libvips and, for team calls, the LiveKit server.

libvips is required even for a bare start: every new user gets a generated
default avatar. Without it, creating a user fails with the misleading
`uninitialized constant Vips::Image` (Active Storage swallows the real "could
not open library 'vips'" error). On macOS:

```sh
brew install vips
```

### LiveKit (team calls)

Team calls need a LiveKit media server. Without it the app runs, but calls
do not connect: "Start call" shows "Could not connect to the call", and Rails
logs a warning on each participant check. The call system tests
(`test/system/call_*_test.rb`) fail without it.

On macOS:

```sh
brew install livekit
```

On Linux, take the release binary that CI pins (`LIVEKIT_VERSION` in
`.github/workflows/ci.yml`, currently v1.13.10) from
https://github.com/livekit/livekit/releases, check it against the release's
`checksums.txt`, and put `livekit-server` on your `PATH`:

```sh
curl -sSfLO https://github.com/livekit/livekit/releases/download/v1.13.10/livekit_1.13.10_linux_amd64.tar.gz
curl -sSfLO https://github.com/livekit/livekit/releases/download/v1.13.10/checksums.txt
sha256sum --check --ignore-missing checksums.txt
tar -xzf livekit_1.13.10_linux_amd64.tar.gz livekit-server
sudo mv livekit-server /usr/local/bin/
```

Use `linux_arm64` instead of `linux_amd64` on ARM machines.

`bin/dev` starts it in development mode when `livekit-server` is on your
`PATH` (its log goes to `log/livekit.log`), and `make livekit` starts it on its
own. Development mode listens on ws://localhost:7880 with the published key
`devkey` and secret `secret`, which `config/environments/development.rb` and
`test.rb` expect; set `LIVEKIT_URL` to use a server elsewhere.

The browser side comes from the `livekit-client` npm package, so an existing
checkout needs `npm ci` again after pulling this change.

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
To try a call with two people, create a second confirmed user who shares a
project with the first (`make newuser` creates the first, test-1@test.com):

```sh
make seconduser
```

Then sign in as test-1@test.com in one browser profile and as test-2@test.com
(password `password1234` for both) in another, for example a second Chrome
profile or a private window, open the board of the shared project in both and
start the call. Browsers allow the camera and microphone on
http://localhost without HTTPS.

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

