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
  `GET /projects/:id/board` (with `change_id` for a change's board, without it
  for the tasks in no change); `GET /projects/:id/statuses` (the board's
  columns); `GET /projects/:id/members`;
- tasks: `/projects/:id/tasks` (list, show, create, update, archive with
  DELETE), and per task `placement`, `subtasks`, `completion`, `label`, `change`
  and `comments`; `PATCH`/`DELETE /comments/:id` for your own comments;
- labels, and changes (list, create, show, update, with `archival`, `tasks`,
  `comments` and `file?path=`) under `/projects/:id`, where a change in a path
  is its id or an open change's name; creating and updating a change take an
  `agent` (an agent's user id, or `null` for any free agent); importing
  OpenSpec changes with `POST /projects/:id/openspec_changes`;
- requests for the steps of a change: `POST /projects/:id/changes/:change/requests`
  asks for one, `POST /projects/:id/changes/:change/agent_release` releases
  the change's agent, and under `/projects/:id/requests` an agent takes one
  with `POST claim`, finishes it with `POST :request/finish` and reports a
  full context with `POST context_full`; anyone cancels one with
  `POST :request/cancellation`;
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
| 403 | `agents_only` | A person's token tried to take a request or report a full context. |
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

## Agents

An agent is an account of its own that works on tasks the way a person does:
it is assigned tasks, moves them, comments, creates tasks and assigns them to
others, including other agents. What it does is recorded as its own doing,
not as that of the person who set it up. How an agent decides what to do (its
runtime, model and budget) is outside Goalner: an agent is whatever program
holds one of its tokens.

Any member creates an agent on a project's **Agents** screen, with a name and
its first token. The agent:

- joins that project at once, without an invitation, and can be added to
  other projects by anyone who shares a project with it;
- gets a generated address such as `silver-fish-4821@agents.goalner.com`. It
  never signs in and never receives email;
- is handled by every member of its projects: they rename it, issue and
  revoke its tokens, remove it from a project, delete it and restore it.
  Whoever created it has no more rights than any other member;
- is marked as an agent wherever a person would be shown.

An agent's token:

- acts as the agent, read-only or read-write, with the same endpoints and
  rate limit as a personal token;
- works at the **API**, through **MCP**, or both, as chosen when it is
  issued. On the other channel it is refused like an unknown token;
- reaches every project that both the agent and the person who issued it
  belong to, as they are at each request. When the issuer leaves a project,
  the token stops reaching it;
- is valid for 100 years, so in practice it does not expire. It ends when
  someone revokes it or the agent is deleted. No password change affects it;
- is shown once, to the person who issues it, who enters their own password
  again. Everyone who can see the agent sees its tokens' names, issuers and
  last use, and can revoke them.

An agent finds its work with the `assigned` view of the task list, which
lists its open tasks and subtasks in a project:

```sh
curl -H "Authorization: Bearer glnr_..." "http://localhost:3000/api/projects/1/tasks?view=assigned"
```

Deleting an agent deletes its tokens for good and unassigns its open tasks in
every project it belongs to. Its comments and finished work stay, marked as a
deleted agent's. Any member of one of its projects can restore it from the
Agents screen; it comes back without tokens and without tasks.

The agent domain must accept no mail. Publish a null MX record for it:

```
agents.goalner.com.  MX  0 .
```

## Changes

Work in a project is grouped into changes. A change is one piece of work,
named as its OpenSpec change is (such as `add-labels`), with its own tasks and
its own board. A project holds any number of open changes; none of them is
"active". The board shows one change at a time, picked from a row of tabs,
plus an **Other tasks** tab for the tasks in no change. The **Changes** screen
lists the open changes with their tasks, adds and moves tasks, and creates and
archives changes.

A change starts from an **idea**: Markdown that says what the work is, given
in the **New change** dialog (or as `idea` to `createChange`). It can be
edited while the change is in Idea, and is fixed once exploring starts, so
that later corrections go into the thread, where an agent sees them as new
input.

A change is in one **phase**: Idea, Exploring, Proposed, Implementing or Done.
A new change starts in Idea. Agents move it with `updateChange`
(`PATCH /api/projects/{project_id}/changes/{change}` with `phase`), and
members can move it to any phase but Done through the API. Taking a request
moves it too (see "Requests and the agent pool").
Importing it moves a change in Idea or Exploring to Proposed. Done is never
set: Goalner reports it while every card of a change in Implementing is in
the done column.

Each change has a **thread** of comments, oldest first, with the same Markdown
and attachments as task comments (`listChangeComments`,
`createChangeComment`). Agents ask their questions there, and people answer
there. While the newest comment of the thread was written by an agent, the
change is **waiting for you**: its board tab and its header on the Changes
screen show a dot. The change's **history** records every phase move and
import with who made it and when, and its page shows these lines among the
comments.

Every change has a page, opened with **Open the change** in the board summary
and from its name on the Changes screen: its phases, its open request and its agent,
the button for its next step, its idea, its thread, and the OpenSpec files of
its last import, each shown formatted or as its source.

### Requests and the agent pool

People ask for the steps of a change on its page, and the project's agents
take them, one change per agent. The button for the next step follows the
phase: **Start exploring** (Idea), **Write the proposal** (Exploring),
**Implement** (Proposed), **Continue implementing** (Implementing) and
**Archive and sync specs** (Done). Text in the comment field goes with the
request as its comment.

- A change has at most one open **request**, waiting or taken. Members cancel
  it with **Cancel request**.
- An agent takes a change with its first request and stays **on** it until
  the change is archived or a member releases it, so the agent that asked a
  question gets its answer. Pick an agent in the **New change** dialog or on
  the page; otherwise the change goes to the first free agent. While an agent
  is on a change, every request of the change waits for that agent.
- A person's comment on a change past Idea with no open request asks the
  change's agent to **reply**. A comment posted while the agent works is
  answered when it finishes. A request for another step replaces a reply
  request that nobody has taken.
- Taking `explore` moves a change in Idea to Exploring, and taking `implement`
  moves it to Implementing. Finishing posts the agent's comment in the
  thread; finishing an archive request archives the change.
- Every take is the agent's **check-in**. An agent without one for 3 minutes
  is offline; set `AGENT_ONLINE_SECONDS` on the server to wait longer, for
  workers that loop more slowly than once a minute. The New change dialog,
  the Agents screen and the change page show which agents are free, which
  change each is on, and which are offline.
- **Release** an agent when its terminal is gone: its taken request is
  cancelled, and the change goes back to any free agent.
- When an agent's context fills up, its change is **blocked**: the change
  waits for people and its page says why. Release the agent and ask for the
  step again; the next agent continues from the change's files, cards,
  commits and thread.

While a change has an open request, its page reloads itself every 10 seconds.
Requests, releases and blocks appear in the change's history.

Archive a change when its work is done: **Archive and sync specs** asks its
agent to archive the OpenSpec change, sync its specs and commit, and then
archives the change in Goalner. **Archive only** archives it at
once, with no agent and no OpenSpec archiving. Either way, its tasks stay
with it and leave the board, whether they are done or not, and a new change
may take its name. An
archived change keeps its page, read-only, at an address with its id.

## OpenSpec changes

Agents that plan with [OpenSpec](https://github.com/Fission-AI/OpenSpec) fill
a change by pushing every file of its folder to Goalner: `tasks.md` becomes
cards, and the proposal, the design and the delta specs are stored for people
to review on the change's page. Goalner never reads the repository: an agent,
script or person sends the text, and saves what comes back.

| In `tasks.md`                     | In Goalner                                                     |
|-----------------------------------|----------------------------------------------------------------|
| the change, such as `add-labels`  | the project's open change `add-labels`, created if there is none |
| a `## 1. Model` section           | a card `add-labels: 1. Model` in that change                   |
| a `- [ ] 1.1 Add the table` item  | a subtask of that card; its extra lines become the description |
| items before the first section    | a card `add-labels: Tasks`                                     |

The cards stay in their change: they cannot be moved to another change or
out of it, since `tasks.md` owns them. Tasks added to the change by hand are
left alone by imports.

Import with `POST /api/projects/{project_id}/openspec_changes`, or with the
MCP tool `importOpenspecChange`, and write the returned `tasks_text` back into
the file. Send `tasks.md` as `tasks`, and, when they exist, `proposal.md` as
`proposal`, `design.md` as `design`, and each `specs/<capability>/spec.md`
under `specs`, keyed by its capability path (`export`, `identity/user-auth`).
The first import of a name creates the change (201), in Proposed; an import
into an open change answers 200, and moves a change in Idea or Exploring to
Proposed:

```sh
dir=openspec/changes/add-labels
artifacts=$(jq -n --rawfile tasks "$dir/tasks.md" '{tasks: $tasks}')
for name in proposal design; do
  if [ -f "$dir/$name.md" ]; then
    artifacts=$(jq --arg name "$name" --rawfile text "$dir/$name.md" '.[$name] = $text' <<<"$artifacts")
  fi
done
for file in $(cd "$dir" && find specs -name spec.md 2>/dev/null); do
  capability=${file#specs/}; capability=${capability%/spec.md}
  artifacts=$(jq --arg key "$capability" --rawfile text "$dir/$file" '.specs[$key] = $text' <<<"$artifacts")
done
jq -n --arg name add-labels --argjson artifacts "$artifacts" '{name: $name, artifacts: $artifacts}' |
  curl --fail-with-body -sS -o import.json -X POST --data-binary @- \
    -H "Authorization: Bearer glnr_..." -H "Content-Type: application/json" \
    http://localhost:3000/api/projects/1/openspec_changes \
  && jq -r .tasks_text import.json > "$dir/tasks.md"
```

The response lists the paths of the stored files but not their text; read one
with `showChangeFile` (`GET /api/projects/{project_id}/changes/{change}/file?path=proposal.md`).
A file that the last import did not send no longer belongs to the change.

The returned text is the file as sent, with each heading and item ending in
its task's key and each item done in Goalner checked:

```markdown
## 1. Model <!-- goalner:GOAL-20 -->

- [x] 1.1 Add the table <!-- goalner:GOAL-21 -->
- [ ] 1.2 Add the model <!-- goalner:GOAL-22 -->
```

The marks are HTML comments, so rendered Markdown hides them, and OpenSpec
still counts the same tasks. Commit them. Later imports find sections and
items by their marks:

- renumbering, rewording or moving an item keeps its task, assignee and
  comments. The text wins over titles and descriptions edited in Goalner;
- unmarked sections and items get new cards and subtasks;
- a task whose mark is gone from the text is archived. Tasks of the change
  that were never marked, such as those added by hand, are left alone;
- a mark may name a task added to the change by hand: that task becomes the
  section's card or the item's subtask, and imports update it from then on;
- a checked item completes its subtask, and a subtask done in Goalner comes
  back checked. An import never reopens anything;
- an import whose text has no marks at all, for a change that already has
  cards from `tasks.md`, is refused with 409 `keys_missing`, so that a lost
  write-back cannot duplicate the change. The 409 carries the marked text to
  save;
- the marks of an archived change are refused: its name may be taken by a new
  change, which starts without marks.

An agent works through a change like this:

1. Read the change's idea (`showChange`) and its thread
   (`listChangeComments`). A person creates the change with its idea; an agent
   may create one too (`createChange`).
2. Move the change to Exploring (`updateChange` with `phase: exploring`), and
   explore. Ask questions in the thread (`createChangeComment`) and wait for
   the answers there; post in the thread only to ask or to report a finished
   step, since an agent's comment marks the change as waiting for people.
3. Write the OpenSpec change, import every file of its folder, and save the
   returned `tasks_text` into `tasks.md`. The change is now Proposed: people
   review the files on its page and answer in the thread. Import again after
   each revision.
4. When told to implement it, move the change to Implementing
   (`updateChange`). Take a card assigned to it (`listTasks` with
   `view=assigned`), assign it to itself if needed, and move it to the work
   column.
5. For each item, do the work, complete its subtask (`completeSubtask` takes
   the key from the mark, such as `GOAL-21`), check its box and commit.
6. Move the card to the done column, and import again. Once every card is in
   the done column, the change is reported Done.
7. When the change is done, archive it (`archiveChange`).

Every request that names a task takes its key as well as its id.

`GET /api/projects/{project_id}/changes/{change}` (`showChange`, with the
change's id or name) returns the change's idea, phase, history and file
paths, the marked text with the current checkboxes, and the change's cards.

Limits and known gaps:

- at most 100,000 characters, 50 sections and 500 items per change. Titles
  longer than 255 characters are cut at a word boundary with `…`, and the
  whole line opens the description;
- the proposal, the design and each spec take at most 100,000 characters, and
  an import at most 50 specs;
- the files are read-only in Goalner, and show the last import, not what is
  committed: ask for changes in the thread;
- tables and other Markdown outside the shared feature set lose their
  structure when a file is shown formatted; its source shows it as imported.

The steps above are the manual way, for an agent driven from its terminal.
With requests, the `goalner-worker` skill does them: see "Running agents"
below.

This repository is developed this way: its own OpenSpec changes go on a
Goalner board, and agents work their cards through MCP.

## Running agents

Each agent of a project's pool is one Claude Code instance on a working copy
of its own, with its own token, running the `goalner-worker` skill
(`.claude/skills/goalner-worker/SKILL.md`) in a loop. On one machine, for
each agent:

1. On the project's **Agents** screen, create the agent with a read-write
   token for **API and MCP**: the skill works through MCP, and its
   compaction hook calls the API.
2. Give it a git worktree of its own:

   ```sh
   git worktree add --detach ../goalner-fish main
   ```

3. Start Claude Code there with the agent's token, test databases of its own,
   and only the MCP server of `.claude/goalner-worker.mcp.json`, which reads
   the token from `GOALNER_TOKEN`:

   ```sh
   cd ../goalner-fish
   GOALNER_TOKEN=glnr_... GOALNER_TEST_DB_SUFFIX=fish \
     claude --strict-mcp-config --mcp-config .claude/goalner-worker.mcp.json
   ```

   `claude mcp add` does not work for this: Claude Code would keep the
   server for the repository, and every worktree would share it.
   `GOALNER_MCP_URL` and `GOALNER_URL` point the server and the hook at
   another Goalner than `http://localhost:3100/mcp` and
   `http://localhost:3000`.
4. In that session, run `/loop 1m /goalner-worker TEST`.

Run one instance per agent: two instances with one token are one agent to
Goalner, and would take each other's requests.

Each agent then:

- learns which agent it is (`showProfile`), and stops if the token is a
  person's;
- every minute takes the next request for it (`claimRequest`). Each take is
  its check-in, so an agent whose loop stops shows as offline after 3
  minutes, or `AGENT_ONLINE_SECONDS` on the server;
- works on each change in a branch named after the change, created from a
  base branch that it asks about in the thread when the idea does not say,
  and commits there. It never pushes;
- does the step: explores and asks, writes and imports the OpenSpec change,
  replies, implements the cards, or archives the OpenSpec change;
- finishes the request with a comment in the change's thread.

When a change is **blocked**, its agent's context filled up: the skill's
`PreCompact` hook (`bin/goalner-context-full`) told Goalner, and stopped
Claude Code from compacting the session into a summary. On the change's
page, choose **Release Fish**, then ask for the step again, such as
**Continue implementing**: the next free agent takes it and continues from
the change's files, cards, commits and thread. Clear or restart the blocked
instance to make it a free agent again.

When an agent's terminal is gone for good, release the agent on its change's
page: its taken request is cancelled, and the change goes back to any free
agent.

The steps of "OpenSpec changes" above remain the manual way to drive an
agent from its terminal.

Goalner never sends to these addresses in any case: every mailer drops them.

## MCP server

AI assistants such as Claude can work with Goalner through the Model Context
Protocol at `https://goalner.com/mcp`. The MCP server offers the token API as
tools, one per JSON operation of `docs/openapi.yaml` (35 of them; file
downloads are left out), named by their `operationId`: `listProjects`,
`showBoard`, `createTask` and so on. Read tools are marked read-only and
deleting tools destructive, so clients can ask before using them.

A client connects in one of three ways:

- **Sign in (OAuth).** The client sends you to Goalner to sign in and approve
  it. The connection reaches **all of your projects**, including ones you join
  later, read-only or read-write as you choose. This is how claude.ai, Claude
  Desktop and mobile, and Claude Code connect.
- **A personal API token** in the `Authorization` header, for one project, as
  below. Clients that cannot sign in use this.
- **An agent's token** in the same header, issued for MCP on a project's
  Agents screen (see [Agents](#agents)). The client then acts as the agent.

Whichever way, the server acts exactly as a token would against `/api`: the same
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

### With an agent's token

Issue a token for the agent on the project's **Agents** screen, with **MCP
only** or **API and MCP**. The screen shows the command to copy, with the
token in it:

```sh
claude mcp add --transport http goalner https://goalner.com/mcp --header "Authorization: Bearer glnr_..."
```

Tool calls are then the agent's: a task it creates has the agent as its
creator. `listTasks` with the view `assigned` lists the agent's own work.

Claude Code keeps a server added this way for the repository it was added
in, git worktrees included, so every working copy of the repository acts as
that one agent. To run several agents on one machine, give each its own
session as in "Running agents" below.

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
| `MCP_SERVICE_KEY` | Secret. The same as the web role's. The key for the connection token exchange. It is also sent with every API request, so the API can tell requests made through MCP from direct ones, which matters for agent tokens issued for one channel only. By itself it authenticates nothing. |
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

The location that sends everything else to the web role must also drop the
`X-Goalner-Service-Key` header: see [DEPLOYMENT.md](DEPLOYMENT.md).

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
and stay signed in; personal tokens are not affected. Agent tokens issued for
one channel only (MCP only, or API only) get the same 503 through MCP, and
"unavailable" tool errors, until the keys match again. Agent tokens for both
channels are not affected.

Для дат всегда юзать ```.current``` ибо он возвращает с учётом ```Time.zone```


Дамп с базы
```pg_dump -O -U deadline -b -Ft -c --if-exists  > deadline.tar```
