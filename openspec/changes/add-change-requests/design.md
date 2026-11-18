# Design

## Context

See proposal.md for why. This change builds on `add-change-conversation`, which is implemented and archived:

- **Change.** `changes.phase` stores `idea`, `exploring`, `proposed` or `implementing`; Done is derived (`Change#phase_reported`). `Change#move_to!(phase, by:)` writes a `phase` event when the phase actually changes. `ChangesController` create and update, and the import, run under the project's lock. `Api::Projects::Changes::ArchivalsController` archives without a lock and without looking at anything but the change.
- **History.** `change_events` holds `phase` and `import` entries; `ChangeSerializer#detail` returns them as `history`, oldest first, and the web client builds each line's text in the viewer's language.
- **Thread.** Comments on a change are created by `Api::Projects::Changes::CommentsController#create` through the `CommentPosting` concern, which reads the body from JSON or multipart, attaches uploads and renders the comment. It takes no lock. `Change.waiting_for_people(changes)` finds open changes whose newest kept comment is an agent's.
- **Change page.** `ChangePage` loads the change and its thread once, and reloads the change after its own actions. Nothing in the client polls.
- **Agents.** An agent is a user with an `Agent` record and memberships in projects. Creating one on the Agents screen issues its first token for the API, MCP or both, shown once; for MCP the screen shows `claude mcp add --transport http goalner <url> --header "Authorization: Bearer <token>"`. Claude Code stores a server added this way for the directory it is run in.
- **MCP.** One tool per JSON operation of `docs/openapi.yaml`. An API answer of 204 becomes the tool result "Done." (`mcp/lib/goalner_mcp/tool_call.rb`), which is why taking a request never answers 204; other errors become tool errors with the envelope's code and message.
- **Workers.** Agents run as Claude Code instances. `/loop` re-runs a prompt or skill until stopped, in the same session, so the session's context carries over from tick to tick. The OpenSpec skills (`openspec-propose`, `openspec-apply-change`, `openspec-archive-change`) know OpenSpec but not Goalner; the Goalner steps are in the README. Tests run in parallel processes against `goalner_test-0` to `goalner_test-N`.
- **Compaction.** When a session nears its context limit, Claude Code compacts it into a summary. A `PreCompact` hook (matcher `auto`) runs just before an automatic compaction and can block it (exit code 2, or `"decision": "block"`); a compaction that was blocked before the limit is skipped and the session goes on uncompacted. Hooks can be declared in a skill's frontmatter, and then apply for the rest of the session once the skill has run. Nothing in Claude Code tells the model or a hook how full the context is before that point.

## Goals / Non-Goals

**Goals:**
- One agent stays on a change from its first request until it is archived, so its context carries the conversation.
- Several agents work one project at once, each an independent Claude Code instance with its own token.
- One table holds requests, and the history, the waiting rule and the change page read from it.
- An agent needs a handful of tools and one skill to work every step.
- Taking a request is safe with several agents on one project.

**Non-Goals:**
- Workers in VMs, pushing or merging (stage 3).
- An agent on several changes at once, or several agents on one change.
- People taking requests.
- Requests that span projects: an agent takes requests one project at a time.
- Timeouts for taken requests or idle agents. A person cancels a request or releases an agent.

## Decisions

### 1. `change_requests`

Columns: `change_id`, `kind` (`explore`, `propose`, `implement`, `archive`, `reply`), `state` (`waiting`, `taken`, `done`, `failed`, `cancelled`), `requested_by_id`, `taken_by_id`, `finished_by_id` (the taker, or whoever cancelled), `taken_at`, `finished_at`, timestamps. Check constraints on `kind` and `state`. A partial unique index on `change_id` where `state IN ('waiting', 'taken')` backs "at most one open request".

The model is `ChangeRequest`, not `Request`, so that it never reads like the controller's `request` in code. In the API and the UI it is a request.

Alternatives:
- *A `requested` flag or phase-like column on `changes`.* It holds one open step, but not who took it, when, or what happened to earlier ones, and the history needs all of that.
- *Solid Queue jobs.* Jobs run inside the Rails process. The worker is outside it, holds only a token and reaches Goalner through the API.

### 2. The agent of a change lives on the change

`changes.agent_id` (the agent's user, nullable), `changes.agent_taken_at` (nullable) and `changes.agent_blocked_at` (nullable, decision 13). The three states:

| `agent_id` | `agent_taken_at` | Meaning |
|---|---|---|
| null | null | no agent: the change's waiting request is in the shared pool |
| set | null | picked: the waiting request is in that agent's queue |
| set | set | on the change: every request of the change goes to that agent |

A partial unique index on `agent_id` where `agent_taken_at IS NOT NULL AND archived_at IS NULL` backs "an agent is on at most one open change", across projects, since one instance has one context. An archived change keeps `agent_id` and `agent_taken_at` as a record of who worked on it; the index no longer counts it, so archiving frees the agent with no write to the agent's side.

Picking sets `agent_id` with `agent_taken_at` null and is refused while `agent_taken_at` is set. Releasing clears all three and writes a `release` event (decision 4).

Alternatives:
- *The agent on each request.* The agent stays across requests, and the next request does not exist yet when the agent should be fixed.
- *A `current_change_id` on agents.* The same fact in two places, and picking a change for an agent that is busy would have nowhere to go.

### 3. Taking a request

`ChangeRequest.take!(project:, agent:)` runs under the project's lock (decision 5) and returns the first of:

1. the agent's own taken request in the project that is not finished, unless its change is blocked;
2. the waiting request of the open change in the project with `agent_id = agent`, `agent_taken_at` set and `agent_blocked_at` null;
3. if the agent is on no open change anywhere: the oldest waiting request (by `created_at`) of an open change in the project with `agent_id = agent` and `agent_taken_at` null;
4. if the agent is on no open change anywhere: the oldest waiting request of an open change in the project with `agent_id` null.

For 2 to 4 it sets the state, taker and time; for 3 and 4 it sets the change's `agent_id` and `agent_taken_at`. It then calls `change.move_to!(:exploring, by:)` for an explore request on a change in Idea, and `change.move_to!(:implementing, by:)` for an implement request. Other kinds leave the phase alone: a proposal moves the change through its import, and an archive request archives it on finishing.

Only agents take requests: the controller answers a person with 403 and the code `agents_only` before anything else. Every take writes the check-in (decision 9) whether or not it returns a request.

The answer is `{"request": {...}}` or `{"request": null}`, always HTTP 200.

### 4. History reads request rows and events

A request's own timestamps say when it was asked for (`created_at`), taken (`taken_at`) and finished or cancelled (`finished_at`), and who did each. `ChangeSerializer#detail` turns each request into up to three history entries (`kind: request`, with `step` and `state` of `asked`, `taken`, `done`, `failed` or `cancelled`) and merges them with `change_events` by time. Phase moves made by taking a request are `phase` events as before. A release is a `change_events` row of kind `release`, with the releasing member as actor and the released agent in a new nullable `agent_id` column. A block (decision 13) is a row of kind `block`, with the agent as actor.

Alternatives:
- *Write a `change_events` row for each request transition.* The same facts would be stored twice and could disagree.

### 5. Every request and agent change runs under the project's lock

Asking for a step, the reply request created by a comment, taking, finishing, cancelling, picking, releasing and archiving all run in `project.with_lock`, as create, update and import already do. This serializes them per project, which is enough for a handful of agents, and keeps the logic plain: read the open request and the agent, decide, write. The two partial unique indexes catch any path that forgets the lock, and the one on `changes.agent_id` also catches one agent taking changes in two projects at the same moment, which the per-project lock does not serialize.

Alternatives:
- *`FOR UPDATE SKIP LOCKED` on waiting requests.* Lets agents take requests in parallel, but taking also moves the phase and the agent, and must not interleave with a comment that creates a reply request. The project lock covers all of it, and the gain matters only with many agents.

### 6. Operations

All paths are under `/api/projects/{project_id}`:

| Operation | What it does |
|---|---|
| `POST /changes/{change}/requests` (`createRequest`) | `kind` (`explore`, `propose`, `implement`, `archive`) and an optional `comment`; 201 with the request; replaces a waiting reply request |
| `POST /requests/claim` (`claimRequest`) | agents only; decision 3; `{request: ...}` or `{request: null}`, always 200 |
| `POST /requests/{id}/finish` (`finishRequest`) | `outcome` (`done` or `failed`) and `comment`; decision 7 |
| `POST /requests/{id}/cancellation` (`cancelRequest`) | cancels an open request; a finished one is left as it is |
| `POST /changes/{change}/agent_release` (`releaseChangeAgent`) | cancels the taken request, clears the agent and its block, writes a `release` event |
| `POST /requests/context_full` (`reportContextFull`) | agents only; decision 13; `{blocked: true}` or `{blocked: false}`, always 200 |
| `POST /changes` and `PATCH /changes/{change}` (`createChange`, `updateChange`) | gain `agent`: an agent's user id to pick it, or `null` for any free agent |

A request in JSON: `id`, `kind`, `state`, `change` (`id`, `name`, `phase`), `requested_by`, `taken_by`, `finished_by` (user cards), `created_at`, `taken_at`, `finished_at`. Changes in lists and in `showChange` gain `request` (the open one, or `null`) and `agent` (`{user: <card>, on: true|false, since: <agent_taken_at>, blocked_at: <agent_blocked_at>}`, or `null`); `ChangeSerializer.list` loads the open requests and agents of all listed changes in one query each. The project's agent list (web only) gains `checked_in_at`, `online` and `working_on` (`{id, name, project_id}` or `null`).

The descriptions of these operations tell an agent what each kind asks for, since the MCP tool description is all that a client without the skill sees:
- `explore`: read the idea, the thread and the code; ask questions by finishing with them, or write the proposal if nothing is unclear;
- `propose`: write the OpenSpec change and import every file of it;
- `reply`: read the comments posted since your last finished request on this change and answer or revise;
- `implement`: work the change's cards until they are done, or finish as failed with what blocks;
- `archive`: archive the OpenSpec change, sync its specs and commit; finishing as done archives the change in Goalner.

### 7. Comments, reply requests and finishing

`CommentPosting` keeps reading the body and attachments. For a change, `CommentsController#create` saves the comment inside `project.with_lock` and then calls `Change#ask_reply_after(comment)`, which creates a reply request asked for by the author when the author is a person, the change is open and past Idea, and it has no open request. `createRequest` saves its comment without that call.

`ChangeRequest#finish!(by:, outcome:, comment:)`, under the lock:
1. refuses unless the request is taken by `by`;
2. sets the state and time, and posts the comment as the agent's;
3. for an archive request finished as done, archives the change (decision 10);
4. otherwise, when a person's kept comment on the change was created after `taken_at`, creates a reply request asked for by the author of the newest one.

Step 4 is what keeps a comment posted during a long step from going unanswered: without it, the agent's finishing comment would become the newest and make the change wait for people.

### 8. Waiting for people

`Change.waiting_for_people` adds one condition: no open request (`NOT EXISTS` on `change_requests` in `waiting` or `taken`). A finished request's comment is the agent's, and makes the change wait for people as soon as the request closes, unless step 4 of decision 7 opened a reply request. A blocked change (`agent_blocked_at` set) is waiting for people whatever its requests and comments, so the board tab and the changes screen mark it with the waiting marker that already exists.

### 9. Check-ins

`memberships.checked_in_at`, written on the agent's membership of the project by every take, whether it returns a request or not. An agent is online in a project while `checked_in_at` is less than 3 minutes old (`Agent::ONLINE_WINDOW`), which is three ticks of `/loop 1m`. One write per agent per minute is cheap.

Alternatives:
- *A separate check-ins table.* It would hold one row per agent and project, which is what memberships already are.
- *Presence from the MCP connection.* The MCP server is stateless HTTP and sees no connection to watch.

### 10. Archiving cancels the open request

`Change#archive!(by:)` runs under the project's lock, cancels the open request as `by`, and sets `archived_at`. The agent is free from then on (decision 2). Finishing an archive request as done marks the request done first, so there is nothing left to cancel. The stage 1 "Archive" action keeps working for changes that were never OpenSpec changes, or when no agent is running.

### 11. Change page

- The next-step button picks its step from the reported phase: Idea `explore`, Exploring `propose`, Proposed and Implementing `implement` (labelled "Implement" and "Continue implementing"), Done `archive` ("Archive and sync specs"). It sends the comment field's text as `comment` and clears the field when the request is created.
- One status line for the request and the agent: "Waiting for a free agent"; "Queued for Fish" with "Fish is on export-csv" or "Fish is offline"; "Fish has been working on it since 14:05"; "Fish's context is full. The change is blocked until you release Fish" for a blocked change; "Fish is on this change" or "Fish is picked" when no request is open. Actions beside it: "Cancel request", "Release Fish" while an agent is on the change, and an agent menu while none is.
- While the change has an open request and `document.visibilityState` is `visible`, the page reloads the change and its thread every 10 seconds, and stops when the request closes.
- The reply note beside the comment field shows under the same condition as decision 7, and names the agent on the change.
- History lines for requests and releases use the same list as phase and import lines.
- The New change dialog lists the project's agents from the agent list, with their states, under "Any free agent".

### 12. Worker

`.claude/skills/goalner-worker/SKILL.md`, run as `/loop 1m /goalner-worker <project>` in a Claude Code instance whose `goalner` MCP server carries one agent's token.

Setup on one machine, per agent:
1. a git worktree of its own, such as `~/dev/goalner-fish`;
2. inside it, the `claude mcp add` command from the Agents screen with that agent's token, which Claude Code keeps for the project directory, so the worktree acts as that agent. Whether Claude Code keys a worktree as its own directory or as the main checkout has to be checked (task 5.3); if it uses the main checkout, each instance starts with `claude --mcp-config <file>` naming a file with its agent's server entry instead;
3. `GOALNER_TEST_DB_SUFFIX` set to a value of its own, which `config/database.yml` appends to the test database name, so two worktrees never share `goalner_test-0` to `-N`.

In a VM (stage 3), the VM's own clone and the token given at start take the place of steps 1 and 2.

One tick:
1. On the first tick, `showProfile`. If the profile is not an agent's, stop and say so; otherwise remember the agent's name. From this tick on, the skill's `PreCompact` hook is active (decision 13).
2. `claimRequest`. Without a request, end the tick.
3. Before the first commit for a change, settle which branch it starts from. When the idea and the thread do not say, the agent asks in the thread: while exploring, as one of its questions; when the first request is a later step, by finishing it as failed with the question, so that the person answers and asks for the step again. It then creates the branch `<change name>` from that base and switches to it; later requests of the change find it checked out. The answer stays in the thread for any agent that takes the change after a release.
4. `showChange`, and the thread with `listChangeComments`, every time: the context carries what the agent did, and the thread brings what people said since.
5. Do the step: `explore` and `reply` read code and answer or ask; `propose` follows the `openspec-propose` skill, validates, then imports `proposal`, `design`, `specs` and `tasks` and saves the returned `tasks_text`; `implement` follows `openspec-apply-change` together with the README's card workflow; `archive` runs `openspec archive` and checks the specs.
6. Run the checks that the step calls for (tests for `implement`, `openspec validate` for `propose` and `archive`), and commit on the change's branch. Never push.
7. `finishRequest` with `done` and what was done or asked, or `failed` with what blocked it.

The skill is the only place that knows both OpenSpec and Goalner. The README's agent workflow points to it, with the setup above.

Alternatives:
- *Dynamic `/loop` without an interval.* The model would pick the delay on each tick, and the guidance it follows suggests long delays for idle ticks, so a request could wait half an hour.
- *A fresh subagent per request, with the loop session only claiming and finishing.* Rejected: each step would start without the questions and answers before it, which is what the thread exists to build up.
- *Put the workflow in `openspec/config.yaml` guidance.* That guidance reaches only OpenSpec's own skills, not the steps around them (taking, importing, finishing).

### 13. A full context blocks the change

The agent was kept on the change for its context. A compacted context is a summary of the questions, answers and reasoning it was kept for, so the agent stops instead of going on with one, and a person decides who continues.

- **Detection.** The worker skill declares a `PreCompact` hook with the matcher `auto` in its frontmatter. It calls `reportContextFull` for the project. When the answer is `{blocked: true}`, the hook blocks the compaction; when it is `{blocked: false}` (a free agent, with nothing to lose), it lets the compaction run. Preferred form: an MCP tool hook that calls the `goalner` server of the session, which already carries the agent's token; if such a hook cannot block a compaction, a command hook running `bin/goalner-context-full` with the agent's token from the environment. Task 5.2 settles which.
- **In Goalner.** `reportContextFull`, under the project's lock: when the agent is on an open change of the project, set `agent_blocked_at`, write a `block` event, answer `{blocked: true}`; otherwise answer `{blocked: false}` and write nothing. The taken request stays taken, so the page shows what the agent was doing. While `agent_blocked_at` is set, a take by that agent returns nothing (decision 3), and the change is waiting for people (decision 8), which marks it on the board tab and the changes screen. The change page says the context is full and offers "Release Fish".
- **After the block.** With compaction blocked, the session runs into the context limit and its turns fail, so the instance does no more harm. A member releases the agent, which cancels the taken request and clears the block, and asks for the step again; the next free agent takes it with an empty context and reads the change's files, cards, commits and thread. The person also clears or restarts the blocked instance, which is then a free agent again.

Alternatives:
- *Let Claude Code compact and go on.* The agent would continue from a summary, which is what keeping one agent per change was meant to avoid.
- *The model notices the summary after a compaction and finishes its request.* The compaction has already happened by then, and a `SessionStart` hook for `compact` adds its text only on the next model request, which mid-turn is not guaranteed.
- *Block when the context reaches a percentage.* Nothing exposes the context's fill level to a hook or to the model; only the status line sees it.

## Risks / Trade-offs

- [A worker crashes with a request taken] → The page shows who took it and since when, and the agent goes offline after 3 minutes. Restarting the same instance resumes the request, since a take returns the agent's unfinished request first. Otherwise a person cancels the request or releases the agent.
- [An agent's instance is gone for good] → A person releases it. The next agent takes the change cold, with only the change and its thread to go on.
- [The picked agent is offline] → Its queue waits, and the page says the agent is offline. A person picks another agent or clears the pick.
- [Two instances run with one agent's token] → Goalner sees one agent; the second instance's take would resume the first's request. The skill and the README say one instance per agent.
- [A long change fills an agent's context] → The change is blocked and a person releases the agent (decision 13). The change's files, cards, commits and thread are what the next agent starts from, which is why the skill commits and comments as it goes.
- [Idle ticks fill the context too] → Every tick adds a call and its answer to the session. An agent that waits days for an answer on its change could block it without doing any work. The skill keeps an idle tick to one `claimRequest` call and no text; dogfooding (task 6.1) shows how long an agent can wait, and a longer interval while the change waits for people is the next lever.
- [The hook cannot block compaction in the form chosen] → Task 5.2 checks both forms against a session with a small auto-compact window before the skill relies on either.
- [An agent posts progress comments while working, then finishes] → While a request is open the change is not waiting, so progress comments do not mark it. The finishing comment does, which is intended.
- [A person replies twice before the agent takes the reply request] → The second comment finds an open request and creates nothing; the agent reads every comment since its last finished request.
- [Archiving through a request needs a running worker] → The stage 1 "Archive" action still archives in Goalner directly.

## Migration Plan

1. Deploy the code and run the migrations: the new table, and new nullable columns on `changes`, `change_events` and `memberships`. All reversible.
2. Restart the MCP server and reconnect MCP clients so they see the new and changed tools.
3. Create the agents on the Agents screen of TEST, each with an MCP token.
4. For each agent: add a worktree, run its `claude mcp add` command inside it, set its test database suffix, start Claude Code there and run `/loop 1m /goalner-worker TEST`.

## Open Questions

- None. Two facts about Claude Code are checked during implementation: whether a worktree has its own MCP settings (task 5.3), and which hook form can block a compaction (task 5.2).
