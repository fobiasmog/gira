# Proposal

## Why

After `add-change-conversation`, a change holds its idea, thread, phase and files, but every step still starts with someone typing into a terminal: "explore export-csv", "the answers are in", "implement export-csv". This is the second half of stage 2. A person asks for the next step in Goalner, and an agent that waits for work takes it, does it and reports back on the change. Once this works with an agent in a terminal on the user's machine, stage 3 only has to move that agent into a VM.

This change builds on `add-change-conversation` and is archived after it.

## What Changes

- **Requests.** A request asks for one step of a change: explore, propose, implement, archive, or reply to new comments. A change has at most one open request. A request is waiting until someone takes it, then taken, then done, failed or cancelled.
- **Asking for a step.** On the change page, a button asks for the step that fits the phase: Start exploring (Idea), Write the proposal (Exploring), Implement (Proposed), Continue implementing (Implementing), Archive and sync specs (Done). Text in the reply field goes along as a comment. Members can cancel an open request.
- **Replies hand the turn back.** A person's comment on a change that is past Idea and has no open request creates a reply request, so an answer to the agent's questions reaches an agent without anyone pressing a button. A request for another step replaces a reply request that nobody has taken yet.
- **Taking and finishing.** An agent takes the next request of a project with one call, which first returns a request it already took and has not finished. Taking an explore request moves a change in Idea to Exploring, and taking an implement request moves it to Implementing. The agent finishes the request as done or failed with a comment that is posted on the change. Finishing an archive request as done archives the change.
- **Waiting for people.** A change with an open request is not waiting for people, whatever its newest comment.
- **History.** Requests asked for, taken, finished and cancelled are shown in the change's history.
- **Worker skill.** A Claude Code skill in this repository describes how an agent takes requests and does each step here: OpenSpec commands, importing into Goalner, tests and commits. It runs under `/loop`, so one terminal session waits for requests.
- **API and MCP.** New operations: `createRequest`, `claimRequest`, `finishRequest` and `cancelRequest`. Changes in lists and in `showChange` carry their open `request`.

Not included:
- running workers anywhere but the user's machine, pushing, opening pull requests or merging (stage 3);
- more than one worker per working copy, or several agents implementing one change at once;
- notifications about finished requests.

## Capabilities

### New Capabilities

- `change-requests`: requests for the steps of a change. Covers:
  - kinds and states, and at most one open request per change;
  - asking for a step, and reply requests created by comments;
  - taking, finishing and cancelling a request, and what each does to the change;
  - the open request in change responses.

### Modified Capabilities

- `changes`: a change with an open request is not waiting for people; the history lists requests.
- `api-tokens`: requests are open to tokens.
- `web-client`: the next-step button, the open request and its cancel action on the change page, and request lines in the thread.

## Impact

- Database: new table `change_requests`, with at most one open request per change enforced by a partial unique index.
- Models: `ChangeRequest`; `Change` (open request, waiting rule, history); comment creation on a change creates reply requests.
- API: request controllers, `ChangeSerializer` (open request, history), change comment creation.
- `docs/openapi.yaml` and through it the MCP tools, with descriptions that tell agents how to work each kind. The MCP server needs a restart and clients a reconnect.
- Web client: the change page's next-step area, request lines in the thread, English and Russian texts.
- Repository: a skill under `.claude/skills/` for the worker, and the README's agent workflow.
