# Design

## Context

See proposal.md for why. This change is planned on top of `add-change-conversation` and assumes its design is built:

- **Change.** `changes.phase` stores `idea`, `exploring`, `proposed` or `implementing`; Done is derived (`Change#phase_reported`). `Change#move_to!(phase, by:)` writes a `phase` event when the phase actually changes. `updateChange`, create and import run under the project's lock.
- **History.** `change_events` holds `phase` and `import` entries; `ChangeSerializer#detail` returns them as `history`, oldest first, and the web client builds each line's text in the viewer's language.
- **Thread.** Comments on a change are created by `Api::Projects::Changes::CommentsController#create`. `Change.waiting_for_people(changes)` finds open changes whose newest kept comment is an agent's.
- **Change page.** `ChangePage` has a header with the phase menu, the thread (comments and history merged by time, `CommentForm`), and the files.
- **MCP.** One tool per JSON operation of `docs/openapi.yaml`. An API answer of 204 becomes the tool result "Done." (`mcp/lib/goalner_mcp/tool_call.rb`), which is why taking a request never answers 204.
- **Workers.** Agents run as Claude Code sessions in this repository. `/loop` re-runs a prompt or skill until stopped. The OpenSpec skills (`openspec-propose`, `openspec-apply-change`, `openspec-archive-change`) know OpenSpec but not Goalner; the Goalner steps are in the README.

## Goals / Non-Goals

**Goals:**
- One table holds requests, and the history, the waiting rule and the change page read from it.
- An agent needs four tools and one skill to work every step: take, then show the change, do the step, finish.
- Taking a request is safe with several agents on one project.

**Non-Goals:**
- Workers in VMs, branches per change, pushing or merging (stage 3).
- Requests that span projects: an agent takes requests one project at a time.
- Timeouts for taken requests. A person cancels a request whose agent has gone away.

## Decisions

### 1. `change_requests`

Columns: `change_id`, `kind` (`explore`, `propose`, `implement`, `archive`, `reply`), `state` (`waiting`, `taken`, `done`, `failed`, `cancelled`), `requested_by_id`, `taken_by_id`, `finished_by_id` (the taker, or whoever cancelled), `taken_at`, `finished_at`, timestamps. Check constraints on `kind` and `state`. A partial unique index on `change_id` where `state IN ('waiting', 'taken')` backs "at most one open request".

The model is `ChangeRequest`, not `Request`, so that it never reads like the controller's `request` in code. In the API and the UI it is a request.

Alternatives:
- *A `requested` flag or phase-like column on `changes`.* It holds one open step, but not who took it, when, or what happened to earlier ones, and the history needs all of that.
- *Solid Queue jobs.* Jobs run inside the Rails process. The worker is outside it, holds only a token and reaches Goalner through the API.

### 2. History reads request rows

A request's own timestamps say when it was asked for (`created_at`), taken (`taken_at`) and finished or cancelled (`finished_at`), and who did each. `ChangeSerializer#detail` turns each request into up to three history entries (`kind: request`, with `step` and `state` of `asked`, `taken`, `done`, `failed` or `cancelled`) and merges them with `change_events` by time. Phase moves made by taking a request are `phase` events as before.

Alternatives:
- *Write a `change_events` row for each transition.* The same facts would be stored twice and could disagree.

### 3. Every request change runs under the project's lock

Asking for a step, the reply request created by a comment, taking, finishing and cancelling all run in `project.with_lock`, as create, update and import already do. This serializes them per project, which is enough for a handful of agents, and keeps the logic plain: read the open request, decide, write. The partial unique index catches any path that forgets the lock.

Alternatives:
- *`FOR UPDATE SKIP LOCKED` on waiting requests.* Lets agents take requests in parallel, but taking also moves the phase and must not interleave with a comment that creates a reply request. The project lock covers both, and the gain matters only with many agents.

### 4. Operations

All paths are under `/api/projects/{project_id}`:

| Operation | What it does |
|---|---|
| `POST /changes/{change}/requests` (`createRequest`) | `kind` (`explore`, `propose`, `implement`, `archive`) and an optional `comment`; 201 with the request; replaces a waiting reply request |
| `POST /requests/claim` (`claimRequest`) | the caller's oldest unfinished taken request, or the oldest waiting one, now taken; `{request: ...}` or `{request: null}`, always 200 |
| `POST /requests/{id}/finish` (`finishRequest`) | `outcome` (`done` or `failed`) and `comment`; posts the comment as the taker's, then archives the change for a done archive request |
| `POST /requests/{id}/cancellation` (`cancelRequest`) | cancels an open request; a finished one is left as it is |

A request in JSON: `id`, `kind`, `state`, `change` (`id`, `name`, `phase`), `requested_by`, `taken_by`, `finished_by` (user cards), `created_at`, `taken_at`, `finished_at`. Changes in lists and in `showChange` gain `request` (the open one, or `null`); `ChangeSerializer.list` loads the open requests of all listed changes in one query.

The descriptions of these operations tell an agent what each kind asks for, since the MCP tool description is all that a client without the skill sees:
- `explore`: read the idea, the thread and the code; ask questions by finishing with them, or write the proposal if nothing is unclear;
- `propose`: write the OpenSpec change and import every file of it;
- `reply`: read the comments posted since the agent's last finished request and answer or revise;
- `implement`: work the change's cards until they are done, or finish as failed with what blocks;
- `archive`: archive the OpenSpec change, sync its specs and commit; finishing as done archives the change in Goalner.

### 5. Comments and reply requests

`Change#post_comment!(author:, body:, files:, ask_reply:)` saves a comment on the change and, when `ask_reply` is true, the author is a person, the change is open and past Idea, and it has no open request, creates a reply request asked for by the author. The change comments controller calls it with `ask_reply: true`; `createRequest` and `finishRequest` call it with `ask_reply: false`. It runs inside the caller's project lock.

### 6. Taking moves the phase

`ChangeRequest#take!(by:)` sets the state, taker and time, then calls `change.move_to!(:exploring, by:)` for an explore request on a change in Idea, and `change.move_to!(:implementing, by:)` for an implement request. Other kinds leave the phase alone: a proposal moves the change through its import, and an archive request archives it on finishing.

### 7. Waiting for people

`Change.waiting_for_people` adds one condition: no open request (`NOT EXISTS` on `change_requests` in `waiting` or `taken`). A finished request's comment is the taker's and, when the taker is an agent, makes the change wait for people as soon as the request closes.

### 8. Change page

- The next-step button picks its step from the reported phase: Idea `explore`, Exploring `propose`, Proposed and Implementing `implement` (labelled "Implement" and "Continue implementing"), Done `archive` ("Archive and sync specs"). It sends the comment field's text as `comment` and clears the field when the request is created.
- The open request shows as a status line ("Waiting for an agent", or "<name> has taken it since <time>") with "Cancel request".
- Beside the comment field, a note says that posting asks an agent to reply, shown when the change is open, past Idea and has no open request: the same condition as decision 5.
- History lines for requests use the same list as phase and import lines.
- The stage 1 "Archive" action stays as it is: it archives in Goalner only, for changes that were never OpenSpec changes or when no agent is running.

### 9. Worker skill

`.claude/skills/goalner-worker/SKILL.md`, run as `/loop /goalner-worker <project>`. One turn:
1. `claimRequest`. Without a request, end the turn: `/loop` waits and calls again.
2. `showChange`, and the thread with `listChangeComments`.
3. Do the step: `explore` and `reply` read code and answer or ask; `propose` follows the `openspec-propose` skill, validates, then imports `proposal`, `design`, `specs` and `tasks` and saves the returned `tasks_text`; `implement` follows `openspec-apply-change` together with the README's card workflow; `archive` runs `openspec archive` and checks the specs.
4. Run the checks that the step calls for (tests for `implement`, `openspec validate` for `propose` and `archive`), and commit on the current branch. Never push.
5. `finishRequest` with `done` and what was done or asked, or `failed` with what blocked it.

The skill is the only place that knows both OpenSpec and Goalner. The README's agent workflow points to it.

Alternatives:
- *Put the workflow in `openspec/config.yaml` guidance.* That guidance reaches only OpenSpec's own skills, not the steps around them (taking, importing, finishing).

## Risks / Trade-offs

- [A worker crashes with a request taken, and the change looks busy forever] → The page shows who took it and since when, and anyone can cancel it. On restart, the same agent's take returns its unfinished request first.
- [Two workers in one working copy edit the same files] → The skill and the README say to run one worker per working copy. Parallel workers wait for stage 3, where each has its own VM.
- [An agent posts progress comments while working, then finishes] → While a request is open the change is not waiting, so progress comments do not mark it. The finishing comment does, which is intended.
- [A person replies twice before an agent takes the reply request] → The second comment finds an open request and creates nothing; the agent reads every comment since its last finished request.
- [Archiving through a request needs a running worker] → The stage 1 "Archive" action still archives in Goalner directly.
- [This change's `changes` delta modifies requirements that only `add-change-conversation` adds] → Archive `add-change-conversation` first; `openspec validate` reports this as information until then.

## Migration Plan

1. Implement and archive `add-change-conversation` first.
2. Deploy the code and run the migration (a new table only; reversible).
3. Restart the MCP server and reconnect MCP clients so they see `createRequest`, `claimRequest`, `finishRequest` and `cancelRequest`.
4. Start a worker in a terminal in this repository: `/loop /goalner-worker TEST`.

## Open Questions

- Which branch a worker commits to when several changes are in flight. For now it commits on the current branch, and the person sets up branches; stage 3 can give each change its own branch without changing the API.
