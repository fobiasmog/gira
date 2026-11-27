# Design

## Context

See proposal.md, "Why". The parts of today's system this design builds on:

- **Agents and their tokens** (specs `agents`, `api-tokens`). An agent is a `users` row with an `agents` row beside it. Its tokens are `api_tokens` rows with an `issuer_id` and `channels`. The check constraint `api_tokens_kind` tells personal, connection and agent tokens apart. An agent token reaches the projects that the agent and its issuer share.
- **Taking a request** (`ChangeRequest.take!`, spec `change-requests`). It records the agent's check-in on its membership. It returns the agent's own taken, unfinished request first, and returns nothing for a blocked change. The same call can therefore serve as a poll, as a heartbeat, and as the signal that a running request has ended. A change's agent lives in `changes.agent_id`, `agent_taken_at` and `agent_blocked_at`.
- **Today's worker** is a Claude Code session in a worktree per agent, running `/loop 1m /goalner-worker <project>` (`.claude/skills/goalner-worker/SKILL.md`). It connects to the MCP server through `.claude/goalner-worker.mcp.json` with `${GOALNER_TOKEN}`. Its `PreCompact` hook, `bin/goalner-context-full`, reports a full context through the API and exits 2 to stop the compaction.
- **Test databases** are named by `GOALNER_TEST_DB_SUFFIX` (`config/database.yml`), which allows letters, digits and underscores only.
- **Claude Code transcripts** are files under `~/.claude/projects/<the working directory, encoded>/<session id>.jsonl`. On this machine, `/Users/evgenii/dev/goalner-fish` maps to `-Users-evgenii-dev-goalner-fish`, so a conversation is tied to the absolute path it ran in.
- **Claude Code headless mode**, per the docs as checked on 2026-11-25:
  - `claude -p` starts a session with `--session-id <uuid>` and continues one with `--resume <uuid>`;
  - `--mcp-config`, `--strict-mcp-config`, `--settings` and the permission mode are not restored on resume and must be passed on every run;
  - two runs must never write to one session at once;
  - SIGINT ends a turn cleanly, and a resumed session keeps an interrupted turn as it was;
  - `--output-format stream-json --verbose` emits an init line with the MCP servers' state, and a final result with `session_id`, `is_error`, `subtype` and `total_cost_usd`, which adds up over resumes;
  - without a permission mode, `-p` refuses everything that needs approval.
- **Not documented** (spike tasks):
  - whether a `PreCompact` hook blocks compaction under `-p`;
  - whether `defaultMode` from `--settings` applies under `-p`;
  - whether `--session-id` refuses an id that is already in use;
  - whether `--resume` finds a session started under another working directory;
  - whether a `Read` deny rule also stops `cat` through Bash outside the sandbox.

## Goals / Non-Goals

**Goals:**
- Nobody handles an agent's token to start, stop or restart it.
- Whatever interrupts a step, it continues as the same request in the same session on the same files.
- Workers hold no identity and no state of their own: Goalner and the workspace hold everything.
- Nothing calls into a machine. A worker needs only to reach Goalner over HTTP.

**Non-Goals:**
- Starting or stopping workers from the app, or scaling them with the queue.
- Moving a workspace between machines, uploading transcripts, or pushing branches.
- Keeping agents away from the runner secret by OS user, container or VM.
- Device-code pairing of runners. Copying the secret once per machine is accepted for now.
- Choosing a change's base branch, and a project's repository address and default branch (decision 8).

## Decisions

### 1. A runner is a machine's credential, not an API token

There is a new table, `runners`, with columns `user_id` (the owner), `name`, `token_digest`, `last_characters` and `last_contact_at`. The secret is `glnr_runner_` followed by 40 base58 characters, and only its SHA-256 digest is stored, as for API tokens. Runner endpoints live under `/api/runner/` and authenticate only with a runner secret, in a concern of their own. Every other endpoint looks secrets up in `api_tokens` only, so a runner secret is unknown there.

Why not an `api_tokens` row: every rule about tokens would then apply by accident, such as the endpoints open to tokens, MCP access, the API document and attribution to the owner. A runner must never act as its owner. Keeping it apart makes "a runner can only lease" true by construction.

A runner ends when its owner's password changes, as personal tokens do. Its run tokens are issued on the owner's authority (decision 2), so a password reset after a compromise must stop them too.

Alternatives:
- *A person's API token in the worker.* The worker could then act as the person on every endpoint open to tokens.
- *Each agent registering itself.* Agents would be created or matched on every start, which leaves duplicates. Goalner's agents are named colleagues who stay on a change, not interchangeable capacity.
- *Device-code pairing* (RFC 8628, as in `gh auth login`), so that nothing is copied at all. It's nicer, but more work on the OAuth server (Doorkeeper 5.9.9, with an extension gem that nobody has checked against it). Deferred.

### 2. Leases and run tokens

There is a new table, `agent_leases`, with columns `agent_id`, `runner_id`, `renewed_at` and `ended_at`, and a partial unique index on `agent_id` where `ended_at` is null.

A lease is live while `ended_at` is null and `renewed_at` is within the lease window: 5 minutes, or `AGENT_LEASE_SECONDS`, read in `config/application.rb` like `AGENT_ONLINE_SECONDS`. A lapsed lease is ended lazily: by the next lease attempt for its agent, or by the next request with its run token. So no job is needed.

A run token is an `api_tokens` row with these properties:
- `issuer_id` is the runner's owner, `channels` is `api_mcp`, and `access` is `read_write`;
- `agent_lease_id` points at its lease. This is a new column, and the `api_tokens_kind` constraint allows it on agent tokens only;
- authenticating with it checks that its lease is live;
- ending the lease deletes the token row.

`Agent#tokens` and the limits on issuing leave out rows with an `agent_lease_id`.

The issuer is the runner's owner so that "Agent token reach" applies unchanged: a run token reaches the projects that the agent and the owner share. The alternative, letting run tokens reach all of the agent's projects, would let a runner reach projects its owner isn't in.

Renewal happens in the requests controller. After `take!`, when the request's token has a lease, it updates `renewed_at`. The take is the worker's heartbeat (10 seconds while waiting, 30 seconds during a run), so the 5-minute window leaves plenty of room.

When the same runner leases an agent again, it replaces its own lease. That lets a crashed worker start again at once without waiting out the window. A second worker on the same machine is stopped by a local lock instead (decision 6).

### 3. A workspace per change, and a session per stint

There is a new table, `workspaces`, with these columns:
- `change_id`, which is unique;
- `runner_id`, `path`, `branch` and `base_branch`;
- `state`: active, kept or removed;
- `head_commit`, `uncommitted` and `checkpoint_at`.

The workspace belongs to the change rather than to the agent for three reasons:
- Git refuses to check out one branch in two worktrees. With a worktree per agent, a second agent couldn't take over a released change while the first agent's worktree still held its branch.
- A handover keeps the uncommitted files.
- The transcripts stay under one fixed path.

The worker derives the path, `<root>/<project short name>/<change name>`. Goalner stores whatever the worker reports and refuses any other path later.

The session of a stint is `changes.agent_session_id`, a UUID:
- `take!` sets it when it puts an agent onto a change (steps 3 and 4);
- it is cleared wherever the agent fields are cleared (release, archive);
- `take!` and the lease fill it in when an agent is on a change without one, which covers changes that were in progress when this change ships.

Goalner chooses the id before anything runs. A crash in the first second still leaves a session the worker can find, and the worker never has to report an id back.

The take filter: `take!` gets the runner of the calling token's lease, or `nil`. In every step it skips changes that have an active workspace of another runner, and for `nil` it skips any change with an active workspace. The same condition sits in the lease, as `workspace_elsewhere`.

### 4. Runner endpoints

| Method and path | What it does |
| --- | --- |
| `GET /api/runner` | The runner's name and its owner's name. `register` uses it to check the secret. |
| `POST /api/runner/agents/:agent_id/lease` | Leases the agent and returns the lease, its run token, the agent, its projects and its current change (spec `agent-runners`, "Lease an agent") |
| `DELETE /api/runner/leases/:id` | Ends the lease and deletes its run token. Ending a lease that has already ended changes nothing. |
| `PUT /api/runner/changes/:change_id/workspace` | Records the change's workspace (`path`, `branch`). Recording the same values again changes nothing. |
| `PATCH /api/runner/workspaces/:id` | Reports a checkpoint (`head_commit`, `uncommitted`) or a state (`removed`, `kept`) |
| `GET /api/runner/workspaces?to_remove=true` | The runner's active or kept workspaces of archived changes |

Errors use the API's JSON envelope. These endpoints aren't opened to API tokens, so they stay out of the OpenAPI document and the MCP tools by the existing rules. The document's verification needs no exception for them.

Session endpoints for people:
- `GET /api/me/runners`, `POST /api/me/runners` (with `name` and `password`), and `DELETE /api/me/runners/:id`;
- `PATCH /api/agents/:id` takes `model` and `instructions`, as well as `name`;
- `POST /api/projects/:id/agents` takes `name`, `model` and `instructions`, with no token fields and no password.

New fields in existing responses:
- the agent list gets `lease`;
- changes get `base_branch` and `workspace`;
- taken requests get `base_branch`, `session_id` and `workspace` on their change.

### 5. The worker program

`bin/goalner-worker` is Ruby with the standard library only (`net/http`, `json`, `yaml`, `open3`, `fileutils`), like `bin/goalner-context-full`. It must run on any machine with Ruby, without the app's bundle. Its code lives in `lib/goalner_worker/`, which is added to the `autoload_lib` ignore list.

The configuration file is `runners.yml` in `$XDG_CONFIG_HOME/goalner/`, or `~/.config/goalner/`. The worker refuses to run when the file's mode allows group or others (`mode & 077`), as ssh does.

`register` merges into the entry for its address. The secret is needed only the first time, because Goalner shows it once. Later calls, with `--clone` for a new project, check and keep the saved secret. Clones are prepared in advance on the machine, and registering is where their folders are named. For a clone without `openspec/`, `register` prints a reminder to run `openspec init`, but doesn't refuse: the folder may be set up later, before the first step is asked for.

The worker runs a single-threaded loop. An `IO.select` on the run's output with a one-second timeout gives it a turn every second, for heartbeats, waits and signals. Runs are spawned with `pgroup: true`, so stopping a run also reaches the test servers and browsers it started.

A run is started like this:

```sh
claude -p "<prompt>" \
  --session-id <id> | --resume <id> \
  --settings  <worker checkout>/.claude/goalner-worker.settings.json \
  --strict-mcp-config --mcp-config <worker checkout>/.claude/goalner-worker.mcp.json \
  --output-format stream-json --verbose \
  [--model <model>] [--append-system-prompt <instructions>]
```

- The worker looks for `~/.claude/projects/*/<id>.jsonl` to choose between `--resume` and `--session-id`. Session ids are UUIDs, so the glob can't match the wrong file, and it doesn't depend on how Claude Code encodes paths.
- The worker's instructions for requests (`lib/goalner_worker/instructions.md`) go into the prompt of the first run of a session only. They stay in the session's context after that, so later runs carry just the request and any notes. A project skill would be read from the workspace's branch, which may be older than the worker. The instructions always come from the worker's own checkout.
- `.claude/goalner-worker.settings.json` is new and committed, beside `goalner-worker.mcp.json`. It sets `permissions.defaultMode` to `auto`, which a headless run needs. It adds a deny rule for reading `~/.config/goalner/**`. It also holds the `PreCompact` hook, matcher `auto`, running `"$GOALNER_WORKER_HOME"/bin/goalner-context-full`. Using a separate file rather than `.claude/settings.json` leaves interactive sessions in the repository as they are.
- The run's environment is the worker's, with `GOALNER_TOKEN`, `GOALNER_URL`, `GOALNER_MCP_URL`, `GOALNER_WORKER_HOME` and `GOALNER_TEST_DB_SUFFIX` set. The runner secret is read from the file and never put into an environment.
- Each run's full output is appended to `log/agents/<agent id>/<request id>.jsonl` in the worker's checkout, which git already ignores. The terminal shows a short form of it.

After a run that left its request unfinished, the worker continues the same session after waiting 1, 5 and then 15 minutes. After the third such run in a row, it finishes the request as failed. This one rule covers dropped connections, overloads and a model that ended its turn without finishing. A retry costs a resumed turn, and a person sees a failure only once the problem has lasted about 20 minutes.

### 6. Local state of the worker

The worker keeps a small state directory, `$XDG_STATE_HOME/goalner/`, or `~/.local/state/goalner/`. It holds, per runner and agent:
- a lock file, held with `flock` while the worker runs. A second worker for the same agent on the machine refuses to start, and the operating system releases the lock when a worker dies;
- the pid and process group of the current run. A worker that starts and finds that process group still running stops it first, so two runs never write to one session.

Nothing else is kept locally: the agent's work lives in Goalner and in the workspace.

### 7. Workspace hooks and test databases

`GOALNER_TEST_DB_SUFFIX` is `c<change id>`, for example `goalner_test_c42`. Change names can be up to 100 characters and contain hyphens, which `config/database.yml` refuses, and Postgres truncates identifiers after 63 bytes. A change's id is short, unique and fixed.

`bin/goalner-attach` runs `bundle check || bundle install`, then `npm install` when `node_modules` is missing or older than `package-lock.json`, then `RAILS_ENV=test bin/rails db:prepare`. `bin/setup` isn't used, because its `db:prepare` runs in development and would apply a branch's migrations to the development database that every worktree shares.

`bin/goalner-detach` drops the change's test databases, including the parallel ones (`_0` to `_N`).

Both hooks are safe to run more than once. Other repositories bring their own hooks, or none.

### 8. Base branch, `main` for now

`changes.base_branch` is new, and it is `main` for every change, existing rows included. The API returns it but doesn't accept it. The worker cuts a change's worktree from it, and the workspace records it. When choosing a base branch comes later, only a way to set it has to be added, and the worker stays as it is.

Choosing the base branch is postponed. The planned way: runners report their clones' local and `origin/*` branches to Goalner, and the New change dialog offers them in a combo box that also takes any typed name. A project's repository address and default branch are postponed with it, because nothing would use them yet.

### 9. Removing the `/loop` worker

`.claude/skills/goalner-worker/` is removed. The README's "Running agents" is rewritten around:
1. creating a runner;
2. `bin/goalner-worker register`;
3. creating agents;
4. `bin/goalner-worker <id>`.

Manual agent tokens still work for interactive sessions, but `take!` gives them nothing from a change with an active workspace (decision 3).

## Risks / Trade-offs

- [A `PreCompact` hook may not block compaction in `-p`] → Spike task 1.1 checks this first. If it doesn't block, the worker watches the context itself: each assistant message in the stream carries the size of the prompt it answered. Past 85% of the window, the worker reports a full context and stops the run.
- [`defaultMode` from `--settings` may not apply in `-p`] → Spike task 1.2. If it doesn't, the worker reads `defaultMode` from the same file and passes it as `--permission-mode`, so the mode is still set in one versioned file.
- [`--resume` may not find a session from another working directory] → Workspace paths never change (decision 3), and the worker adds the "context lost" note when no transcript is found.
- [The agent can read the runner secret] → Claude runs as the same OS user. The deny rule covers Claude's Read tool, and spike task 1.4 checks whether it also stops Bash. The secret can only lease agents the owner can see, the owner can revoke it at once, and it ends with a password change. Only a separate OS user or a VM closes this, which belongs to stage 3.
- [Two machines sharing one runner secret] → The same runner on two machines would take the same agent's lease from each other. The README says to register each machine as its own runner, and a worker that loses its lease twice within 10 minutes stops.
- [The worker's own checkout changes under it] → When a person switches branches in the checkout that holds `bin/goalner-worker`, the instructions and settings for the next run change too. The README recommends running workers from a checkout of `main`. The workspaces are separate worktrees and aren't affected.
- [Unattended runs on a subscription login] → Workers use the user's own `claude` login and share the plan's limits. `ANTHROPIC_API_KEY` in the worker's environment switches runs to API billing. The README says so.
- [A branch with the change's name already exists] → The worker refuses and finishes the request as failed, naming the branch, instead of continuing someone else's work. The person renames the change or deletes the branch.

## Migration Plan

1. Stop the `/loop` sessions of Fish and Heron. Commit or discard their work. Release them from their changes, or let those changes finish. Then remove their worktrees (`git worktree remove ../goalner-fish`, and the same for Heron), so that the change branches are free to be checked out in workspaces.
2. Merge and migrate. Existing changes get the base branch `main`.
3. In Goalner: Settings, Runners, create "laptop". Copy the register command and run it with `--clone TEST=~/dev/goalner`.
4. Start each agent with `bin/goalner-worker <id>`, from a checkout of `main`.

Rollback: revert the merge and roll back the migrations. The `/loop` skill and agent tokens issued by people work as before. Workspaces on disk remain as ordinary worktrees.

## Open Questions

- Device-code pairing for runners, so that the secret isn't copied even once. It would add a way in without changing the specs here.
- Whether people should be able to remove a kept workspace from the change page, or only on the machine.
