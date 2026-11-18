## 1. Data model

- [ ] 1.1 Add the migration for `change_requests` (design decision 1): columns, check constraints on `kind` and `state`, the partial unique index on `change_id` for open requests, and an index for taking the oldest waiting request of a project; verify that `bin/rails db:migrate` and a rollback succeed, and that the database refuses a second open request on one change.
- [ ] 1.2 Add `ChangeRequest` with `ask!`, `take!`, `finish!` and `cancel!` under the project's lock (design decisions 3 and 6), and `Change#open_request`; verify with model tests for every scenario of "Requests for the steps of a change", "Take a request", "Finish a request" and "Cancel a request".
- [ ] 1.3 Add `Change#post_comment!` with reply requests (design decision 5); verify with model tests for every scenario of "Reply requests", and that a comment posted while asking for a step creates no reply request.
- [ ] 1.4 Add the open-request condition to `Change.waiting_for_people` (design decision 7); verify with model tests for every scenario of "Waiting for people", including "Request open".

## 2. API

- [ ] 2.1 Add `Changes::RequestsController#create` (`createRequest`, 201, the comment, replacing a waiting reply request, 422 for a reply kind, an open request or an archived change); verify with controller tests for every scenario of "Ask for a step".
- [ ] 2.2 Add `RequestsController` with `claim` (`claimRequest`, always 200, `request: null` when none), `finish` (`finishRequest`) and `cancellation` (`cancelRequest`); verify with controller tests for "Oldest waiting request", "Nothing waiting", "Resume", "Implement moves the phase", the finish scenarios and the cancel scenarios, and a test that two takes in parallel threads get one request between them.
- [ ] 2.3 Route change comments through `Change#post_comment!`; verify with controller tests for "Answer to an agent's questions", "Agent's comment", "Comment in Idea" and "Comment while a request is taken".
- [ ] 2.4 `ChangeSerializer`: `request` in lists and in the detail with the open requests loaded in one query, and request entries in `history` (design decision 2); verify with tests for "Taken request in the list", "No open request" and "A request from start to end", and a query-count assertion on the changes list.
- [ ] 2.5 Open the request endpoints to tokens; verify with request tests for the `api-tokens` scenarios "Requests" and "Requests with a read-only token".

## 3. API document and MCP

- [ ] 3.1 Update `docs/openapi.yaml`: the four operations, the request schema, `request` on changes, request entries in `history`, and descriptions that say what each kind asks an agent to do (design decision 4); verify that `bin/openapi-verify` and the examples contract test pass.
- [ ] 3.2 Verify with MCP tests that the tool list has `createRequest`, `claimRequest`, `finishRequest` and `cancelRequest`, that `claimRequest` with an agent token returns `{"request": null}` as JSON text when nothing is waiting, and that `finishRequest` posts the comment as the agent.

## 4. Web client

- [ ] 4.1 Types and API calls for requests, `request` on changes and request history entries; verify that `npm run typecheck` passes.
- [ ] 4.2 The change page's next-step button, the open request's status line with "Cancel request", and the reply note beside the comment field (design decision 8); verify with a frontend test for the step chosen in each phase, and system tests for "Start exploring", "Button for the phase", "Comment with the step", "Taken request", "Cancel", "Reply note" and the page scenario "Archived change".
- [ ] 4.3 Request lines in the thread, in the viewer's language; verify with a system test for "Request lines in the thread".
- [ ] 4.4 English and Russian texts; verify that `npm test`, `npm run typecheck` and `npm run policy` pass, and that `bin/rails test:system` passes after `npx vite build --mode test`, apart from the two failures known on this machine.

## 5. Worker

- [ ] 5.1 Add `.claude/skills/goalner-worker/SKILL.md` (design decision 9): taking a request, the work for each kind, checks, committing on the current branch without pushing, finishing as done or failed, one worker per working copy; verify that Claude Code lists the skill and that a dry run against an empty project ends its turn after `claimRequest` returns no request.
- [ ] 5.2 README: requests in the API list, and the agent workflow rewritten around `/loop /goalner-worker <project>`, with the terminal steps of `add-change-conversation` kept as the manual way; verify that it matches `docs/openapi.yaml`.

## 6. Dogfooding

- [ ] 6.1 Run a change through every step without typing into the worker's terminal: restart the MCP server and reconnect, start `/loop /goalner-worker TEST`, create a small change with an idea in TEST, choose "Start exploring", answer the agent's questions in the thread, choose "Write the proposal" if it has not proposed, review the files, choose "Implement", and choose "Archive and sync specs" when it is Done; verify that the change ends archived, that its history lists every request, and that the commits are on the current branch.
- [ ] 6.2 When archiving this change, after `add-change-conversation`: update the Purpose of the `changes` spec to mention requests; verify that `openspec validate --specs --strict` passes.
