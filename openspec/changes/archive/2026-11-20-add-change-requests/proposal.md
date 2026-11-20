# Proposal

## Why

After `add-change-conversation`, a change holds its idea, thread, phase and files, but every step still starts with someone typing into a terminal: "explore export-csv", "the answers are in", "implement export-csv". This is the second half of stage 2. A person asks for the next step in Goalner, and an agent from the project's pool takes it, does it and reports back on the change.

The agent that takes a change keeps it until the change is archived. Its context carries every question, answer, proposal and line of code in between, so a reply to its questions reaches the agent that asked them. Each agent is an independent Claude Code instance with its own token. Once this works with instances in terminals on the user's machine, stage 3 only has to run the same instances in VMs.

This change builds on `add-change-conversation` and is archived after it.

## What Changes

- **Requests.** A request asks for one step of a change: explore, propose, implement, archive, or reply to new comments. A change has at most one open request. A request is waiting until an agent takes it, then taken, then done, failed or cancelled.
- **Asking for a step.** On the change page, a button asks for the step that fits the phase: Start exploring (Idea), Write the proposal (Exploring), Implement (Proposed), Continue implementing (Implementing), Archive and sync specs (Done). Text in the reply field goes along as a comment. Members can cancel an open request.
- **The agent pool.** An agent works on one change at a time. It takes a change with the change's first request and stays on it until the change is archived or a person releases it. In the New change dialog, a member can pick an agent for the idea; picking says who, and the button says when. Once a step is asked for, a change with an agent picked waits in that agent's queue, and any other change waits in the project's shared pool for the first free agent. While no agent is on a change, members can pick another agent or clear the pick.
- **Taking and finishing.** Only agents take requests. An agent takes with one call, which returns the first of: its own taken request that is not finished, a waiting request on its change, the oldest waiting request in its queue, the oldest waiting request in the shared pool. Taking an explore request moves a change in Idea to Exploring, and taking an implement request moves it to Implementing. The agent finishes the request as done or failed with a comment that is posted on the change. Finishing an archive request as done archives the change.
- **Replies hand the turn back.** A person's comment on a change that is past Idea and has no open request creates a reply request, which goes to the change's agent. A comment posted while an agent has a request taken creates a reply request when that request finishes, so the agent does not miss it. A request for another step replaces a reply request that nobody has taken yet.
- **Check-ins.** Every take records the agent's check-in in the project. An agent without a check-in for 3 minutes, or as long as the server is configured to wait, is offline. The New change dialog, the Agents screen and the change page show which agents are free, which change each one is on, and which are offline.
- **Releasing.** A member can release a change's agent, for example when its terminal is gone. Its taken request is cancelled, and the change goes back to the shared pool.
- **Full context.** When an agent's context fills up, the agent does not let Claude Code summarise it: a hook stops the compaction and reports the full context to Goalner. The change is blocked: its agent gets no more of its requests, the change waits for people, and its page says why. A member releases the agent, and the next agent continues from the change's files, cards and thread.
- **Archiving.** Archiving a change cancels its open request, which frees its agent.
- **Waiting for people.** A change with an open request is not waiting for people, whatever its newest comment.
- **History.** Requests asked for, taken, finished and cancelled, and releases, are shown in the change's history.
- **Change page.** While a change has an open request, its page refreshes itself.
- **Worker skill.** A Claude Code skill in this repository describes how an agent works: it learns which agent it is, takes requests, and does each step with the context of the earlier ones: OpenSpec commands, importing into Goalner, tests and commits on a branch for the change. It runs under `/loop`. Locally, each agent runs in its own git worktree, connected with its own token, with its own test databases.
- **API and MCP.** New operations: `createRequest`, `claimRequest`, `finishRequest`, `cancelRequest`, `releaseChangeAgent` and `reportContextFull`. Creating and updating a change take an `agent`. Changes in lists and in `showChange` carry their open `request` and their `agent`.

Not included:
- running workers anywhere but the user's machine, pushing, opening pull requests or merging (stage 3);
- an agent on more than one change at a time, or several agents on one change;
- people taking requests;
- notifications about finished requests.

## Capabilities

### New Capabilities

- `change-requests`: requests for the steps of a change, and the agents that take them. Covers:
  - kinds and states, and at most one open request per change;
  - asking for a step, and reply requests created by comments;
  - the agent of a change: picking it, its queue, the shared pool, releasing it;
  - taking, finishing and cancelling a request, and what each does to the change;
  - check-ins, and agents being online or offline;
  - blocking a change when its agent's context is full;
  - the open request and the agent in change responses.

### Modified Capabilities

- `changes`: creating a change can pick its agent; archiving cancels the open request; a change with an open request is not waiting for people unless it is blocked; the history lists requests, releases and blocks.
- `api-tokens`: requests, releasing and reporting a full context are open to tokens.
- `web-client`: the agent picker in the New change dialog; agents' states on the Agents screen; the next-step button, the open request, its agent, a block and their actions on the change page, which refreshes while a request is open; request, release and block lines in the thread.

## Impact

- Database: new table `change_requests`, with at most one open request per change enforced by a partial unique index. `changes` gains its agent, when the agent took it and when it was blocked, with at most one open change per agent enforced by a partial unique index. `memberships` gains the last check-in. `change_events` gains the released agent.
- Models: `ChangeRequest`; `Change` (agent, open request, waiting rule, history, release); comments on a change create reply requests; finishing a request creates late reply requests; archiving cancels the open request.
- API: request controllers, the release endpoint, `agent` on change create and update, `ChangeSerializer` (open request, agent, history), change comment creation, agent states in the project's agent list.
- `docs/openapi.yaml` and through it the MCP tools, with descriptions that tell agents how to work each kind. The MCP server needs a restart and clients a reconnect.
- Web client: the New change dialog, the Agents screen, the change page's request area and refresh, request and release lines in the thread, English and Russian texts.
- Repository: a skill under `.claude/skills/` for the worker, with the hook that stops compaction; the test database name takes a suffix per worktree; the README's agent workflow.
