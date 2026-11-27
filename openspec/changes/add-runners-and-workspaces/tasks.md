## 1. Spikes: Claude Code headless

- [x] 1.1 Check whether a `PreCompact` hook with matcher `auto`, given through `--settings`, stops an automatic compaction in `claude -p` when it exits with 2; verify by running a `-p` session with `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` set low and a hook that logs and exits 2, and record the Claude Code version and the result in design.md (fallback in "Risks / Trade-offs").
- [x] 1.2 Check whether `permissions.defaultMode: auto` from a `--settings` file applies in `claude -p`; verify with a run that edits a file and runs a shell command without prompting, and record the result in design.md.
- [x] 1.3 Check what `claude -p --session-id <id>` does with an id already in use, and whether `claude -p --resume <id>` finds a session started under another working directory; verify both by hand and record the answers in design.md.
- [x] 1.4 Check whether a `Read` deny rule on `~/.config/goalner/**` also stops `cat` of that file through Bash in auto mode outside the sandbox; verify by hand and record the result in design.md.

## 2. Data model

- [x] 2.1 Add migrations for `runners`, `agent_leases` (partial unique index on `agent_id` where `ended_at` is null), `workspaces` (unique `change_id`, state check), `api_tokens.agent_lease_id` with the widened `api_tokens_kind` constraint, `changes.base_branch` (`main`, existing rows included) and `changes.agent_session_id`, and `agents.model` and `agents.instructions`; verify that `bin/rails db:migrate` and a rollback succeed, and that the database refuses a second live lease of one agent and a second workspace of one change.
- [x] 2.2 Add `Change#base_branch`, `main` for every change (design decision 8); verify with model tests for every scenario of "Base branch of a change".
- [x] 2.3 Add agent settings (`model`, `instructions`) with their validations; verify with model tests for every scenario of "Agent settings".
- [x] 2.4 Add `Runner`: creation with a `glnr_runner_` secret stored as a digest, the limit of 10, rotating its secret and revoking it, both of which end its leases, and runners left as they are by a password change (design decision 1); verify with model tests for the scenarios of "Runners" and "List, rotate and revoke runners".
- [x] 2.5 Add `AgentLease`: leasing with its run token, one live lease per agent, replacing the same runner's lease, `agent_leased` and `workspace_elsewhere`, lazy lapse after `AGENT_LEASE_SECONDS`, ending that deletes the run token, and ending on agent deletion (design decision 2); verify with model tests for every scenario of "Lease an agent", "One lease per agent" and "Renewing and ending a lease".
- [x] 2.6 Leave run tokens out of `Agent#tokens` and the issuing limits, and refuse a run token whose lease is not live in token authentication; verify with tests for "Run tokens", "Run tokens do not count", "Run token left out" and "Run token ends with its lease".
- [x] 2.7 Add `Workspace`: recording (same values succeed, another path or branch refused), staying on its runner, checkpoints, the states and the list to remove (design decision 3); verify with model tests for every scenario of "Workspace of a change", "Workspace on one machine", "Checkpoints" and "Removing workspaces".
- [x] 2.8 Extend `ChangeRequest.take!` with the session of a stint (set when an agent comes onto a change, cleared with the agent, filled in when missing) and the workspace filter by the calling lease's runner (design decision 3); verify with model tests for every scenario of "Session of a stint" and the new scenarios of "Take a request", and that the existing take tests still pass.

## 3. API

- [x] 3.1 Add runner authentication for `/api/runner/` and `GET /api/runner`: runner secrets only, 401 for sessions and API tokens, runner secrets unknown everywhere else, no CSRF, 300 requests a minute and 60 leases an hour, `last_contact_at` to within a minute (design decisions 1 and 4); verify with request tests for every scenario of "Runner authentication" and the new `security-baseline` scenarios.
- [x] 3.2 Add the lease and release endpoints with the lease response (agent, settings, projects, current change with base branch, session, workspace and taken request); verify with controller tests for every scenario of "Lease an agent" and "One lease per agent", and "Release" of "Renewing and ending a lease".
- [x] 3.3 Add the workspace endpoints (record, checkpoint and state, list to remove); verify with controller tests for the scenarios of "Workspace of a change", "Workspace on one machine", "Checkpoints" and "Removing workspaces".
- [x] 3.4 Add the session-only runner endpoints under `/api/me/runners` (list, create and rotate with password and lockout, revoke); verify with controller tests for the scenarios of "Runners" and "List, rotate and revoke runners", including 403 for any token.
- [x] 3.5 Create agents without a token or password and with settings, edit settings with `PATCH /api/agents/:id`, and add `lease` to the project's agent list; verify with controller tests for the modified "Create an agent in a project" and "Who can see and handle an agent", "Agent settings" and "Leases in the agent list".
- [x] 3.6 Add `base_branch` and `workspace` to change lists and the detail, loaded for all listed changes in one query, and ignore a `base_branch` given on create; verify with controller tests for "Base branch of a change" and "Workspace in change responses", and a query-count assertion on the changes list.
- [x] 3.7 Add `base_branch`, `session_id` and `workspace` to the change of a taken request, and renew the lease of a run token on every take; verify with controller tests for "Base branch, session and workspace" and "Lapse" of "Renewing and ending a lease".
- [x] 3.8 Filter runner secrets from logs and error reports; verify with a test that a lease request is logged with its `Authorization` header filtered.

## 4. API document and MCP

- [x] 4.1 Update `docs/openapi.yaml`: agent create without token fields and with settings, `PATCH` agent settings, `lease` on agents, `base_branch` and `workspace` on changes, `base_branch`, `session_id` and `workspace` on taken requests, with no runner endpoints; verify that `bin/openapi-verify` and the examples contract test pass.
- [x] 4.2 Verify with an MCP test that `claimRequest` with a run token returns the change's base branch, session and workspace, and that the tool list has no runner operation.

## 5. Worker program

- [x] 5.1 Create `bin/goalner-worker` and `lib/goalner_worker/` with the standard library only, add `goalner_worker` to the `autoload_lib` ignore list, and build the test harness: a stand-in Goalner API in `test/support/` and a stand-in `claude` (through `CLAUDE_BIN`) that records its arguments and environment, writes stream-json, and finishes, fails, hangs or ignores SIGINT as told; verify that an empty worker test runs.
- [x] 5.2 Add `register` and the configuration file: `$XDG_CONFIG_HOME`, permissions 600 and 700, one entry per address, `--token` optional for a saved address, clones merged and checked, the `openspec init` reminder, and the refusal of a file readable by others; verify with tests for every scenario of "Register a runner" and "Configuration file safety".
- [x] 5.3 Add starting by agent id: the arguments, choosing the runner, the local lock, the lease and its refusals, and projects without a clone (design decision 6); verify with tests for every scenario of "Start an agent by its id".
- [x] 5.4 Add waiting: a round of takes every 10 seconds, the backoff while Goalner is down, and leasing again after 401 at most once in 10 minutes; verify with tests for every scenario of "Waiting for a request", with the waits shortened by environment variables.
- [x] 5.5 Add attaching: creating or reusing the worktree from the project's clone and the base branch, the refusals, recording the workspace, recreating a missing worktree with the "files lost" note, and the attach hook; verify with tests against a temporary git repository for every scenario of "Attach to a workspace".
- [x] 5.6 Add running a request: the prompt with the instructions on a session's first run and the notes, `--session-id` or `--resume` chosen by the transcript, the settings, MCP configuration, model and instructions on every run, the environment without the runner secret, the log file and the terminal output (design decision 5); verify with tests for every scenario of "Run a request".
- [x] 5.7 Write `lib/goalner_worker/instructions.md` for the five kinds of request and the rules of "One request per run"; verify by review against the requirement, and with a test that the first run's prompt holds it and a resumed run's prompt doesn't.
- [x] 5.8 Add the heartbeat during a run and stopping it (same request, none, another, 401 with a new lease; interrupt, terminate, kill); verify with tests for every scenario of "Heartbeat and stopping a run".
- [x] 5.9 Add what happens after a run: the checkpoint, resuming after 1, 5 and 15 minutes, and failing after the third unfinished run; verify with tests for every scenario of "After a run".
- [x] 5.10 Add stopping and restarting: releasing on SIGINT and SIGTERM, and stopping a run left by a killed worker from the state directory (design decision 6); verify with tests for every scenario of "Stop and restart the worker".
- [x] 5.11 Add removing finished workspaces at start and after an archive request: the detach hook, removing without forcing, kept and removed; verify with tests for every scenario of "Remove finished workspaces".
- [x] 5.12 Add `.claude/goalner-worker.settings.json` with the permission mode, the deny rule and the `PreCompact` hook through `GOALNER_WORKER_HOME`, adjusted to the spike results; verify that `test/bin/goalner_context_full_test.rb` passes with a run token, and with a test for "Context fills during a step" against the stand-ins.
- [x] 5.13 Add `bin/goalner-attach` and `bin/goalner-detach` (design decision 7); verify by running them in a temporary worktree with `GOALNER_TEST_DB_SUFFIX=c0`, checking that the test databases are created and then dropped and that the development database's schema version is unchanged.

## 6. Web client

- [x] 6.1 Types and API calls for runners, leases, agent settings, base branches and workspaces; verify that `npm run typecheck` passes.
- [x] 6.2 Add the Runners screen, with creating, rotating and revoking; verify with system tests for every scenario of "Runners screen" and "Runners entry".
- [x] 6.3 Change the Agents screen: create without a token with optional settings and the start hint, edit settings, where each agent runs, and issuing tokens with a password; verify with system tests for every scenario of the modified "Agents screen".
- [x] 6.4 Add the base branch and the workspace to the change page; verify with system tests for every scenario of "Workspace on the change page".
- [x] 6.5 English and Russian texts; verify that `npm test`, `npm run typecheck` and `npm run policy` pass, and that `bin/rails test:system` passes after `npx vite build --mode test`.

## 7. Workflow and docs

- [x] 7.1 Remove `.claude/skills/goalner-worker/`, and rewrite the README's "Running agents". It covers:
  - creating a runner, and registering each machine as its own runner;
  - preparing a project: clone its repository, run `openspec init` and commit it, make a first commit on `main` if the repository is empty, and register the clone with `bin/goalner-worker register --url … --clone <PROJECT>=<path>`;
  - creating agents, and starting them with `bin/goalner-worker <id>` from a checkout of `main`;
  - restarting running workers after registering a new project, and registering a clone again after its project's short name changes;
  - the subscription login and `ANTHROPIC_API_KEY`;
  - the migration steps.

  Verify that no file in the repository still mentions `/loop /goalner-worker`.

## 8. End to end

- [x] 8.1 Follow design.md's "Migration Plan" on this machine with Fish and Heron on TEST, then run a test change through every step. Verify:
  - "Start exploring" creates the workspace and its session;
  - Ctrl-C during a step, then `bin/goalner-worker <id>`, resumes the same session;
  - releasing Fish gives Heron the same workspace with a new session;
  - archiving removes the workspace.

  Record what happened in this task.

  Done on 2026-11-27 with Claude Code 2.1.332. Migration: the `/loop` sessions were no longer running and their worktrees were clean. Agents Fish (6) and Heron (7) were deleted, with their worktrees, branches (`changes-empty-hint`, `agent-count-badge`) and test databases, and created again as Fish (8, no model) and Heron (9, `sonnet`). Runner "laptop" was created for TEST's owner and registered with `--clone TEST=~/dev/goalner`. The workers ran from this branch's checkout, in a clean environment (`env -i`), against `bin/dev`. Test change `e2e-hello` (change 12):
  - "Start exploring": Fish's worker created `~/goalner/workspaces/TEST/e2e-hello` on the new branch `e2e-hello` from `main`, and Goalner recorded it on "laptop". It started session `177bb15b…` with `--session-id`, whose transcript was written under `~/.claude/projects/-Users-evgenii-goalner-workspaces-TEST-e2e-hello/`. Nothing was unclear, so the run went on to propose: OpenSpec files, an import (card TEST-95), commit `9bf682e`, finished as done in 46 seconds. The checkpoint `9bf682e` was reported, with nothing uncommitted.
  - Ctrl-C: after "Implement", SIGINT to the worker 4 seconds into the run stopped the run, released the lease, and exited 0. Request 11 stayed taken by Fish. `bin/goalner-worker 8` leased again and continued the same session with `--resume` and the "interrupted" note. Only the session's first prompt held the instructions. Fish added `docs/e2e-hello.md` (commit `ae7752c`) and finished; the change reported Done.
  - Handover: releasing Fish cleared the session. With Heron picked, "Archive" went to Heron's worker, which used the same workspace path and started a new session (`0886ef80…`) with `--model sonnet`. It archived the OpenSpec change (commit `fab78ac`) and finished as done.
  - Archiving: right after that run, Heron's worker removed the worktree. The workspace became removed in Goalner, and the branch stayed. Runs used auto mode, and the `goalner` MCP server was connected.
- [x] 8.2 Fill a run's context on purpose during an implement step; verify that the change is blocked, the compaction doesn't run and the worker stops the run, or that the fallback chosen in task 1.1 does the same.

  Done on 2026-11-27, with the worker started with `CLAUDE_CODE_AUTO_COMPACT_WINDOW=100000 CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=40`, so Claude Code tried to compact on its first turns.
  - First try (change 13): the hook ran 6 seconds into the run, Goalner blocked the change, and no compaction ran. But the run went on, and the model wasn't told, so it finished its request 17 seconds later, before the 30-second heartbeat.
  - Fix: the worker now takes a request as soon as the run's stream reports a compaction (a `status` line). A worker test with a 60-second heartbeat covers it, and it fails on the old worker.
  - Second try (change 14): the change was blocked 6 seconds in, the run was stopped within a second, no `compact_boundary` appeared, and request 14 stayed taken by Fish. Releasing Fish and archiving the change, then starting a worker, removed its workspace.
- [ ] 8.3 Run the whole test suite, `bin/rubocop`, `bin/brakeman` and `bin/openapi-verify`; verify that all pass.

  On 2026-11-27, after the 8.2 fix: the suite (1,272 tests, worker tests included) passes, the system tests passed (206, `TZ=UTC`, after `npx vite build --mode test`), and `bin/rubocop` and `bin/openapi-verify` pass. `bin/brakeman` has one warning, which predates this change: Ruby 4.0.7 in `.ruby-version` (CVE-2026-132825, fixed in 4.0.10). Left open until Ruby is upgraded or the warning is accepted.

## 9. Starting agents by name

- [x] 9.1 Add `GET /api/runner/agents`, listing the agents the runner can run with their projects and live leases; verify with controller tests for "Agents a runner can run".
- [x] 9.2 Let `bin/goalner-worker` take an agent's name, any letter case, or `PROJECT/Name`, preferring the one agent with a cloned project, and list the agents with their start commands when given no argument; verify with worker tests for every scenario of "Start an agent".
- [x] 9.3 Show each agent's start command on the Agents screen, after creating it and from its menu, by name or by id when the name is shared in the project, quoted for the shell; verify with unit tests for the command and system tests for "Create" and "Start command" of the "Agents screen".
- [x] 9.4 Update the README's "Running agents" and the worker's messages to start agents by name; verify that `bin/goalner-worker <agent id>` appears nowhere as the way to start an agent.

