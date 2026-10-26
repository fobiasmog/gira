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
  `GET /projects/:id/board`; `GET /projects/:id/members`;
- tasks: `/projects/:id/tasks` (list, show, create, update, archive with
  DELETE), and per task `placement`, `subtasks`, `completion`, `label`, `sprint`
  and `comments`; `PATCH`/`DELETE /comments/:id` for your own comments;
- labels, milestones (with `recovery`), and sprints (with `activation`,
  `archival` and `tasks`) under `/projects/:id`;
- downloads of attachments and avatars from the `/files/...` URLs in responses.

Everything else (projects, members, invitations, columns, your account,
tokens, teammates, statistics, announcements and feedback) answers a token
with 403. See `config/routes.rb` for the exact paths and parameters.

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

Для дат всегда юзать ```.current``` ибо он возвращает с учётом ```Time.zone```


Дамп с базы
```pg_dump -O -U deadline -b -Ft -c --if-exists  > deadline.tar```
