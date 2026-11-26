## 1. Spikes: Claude Code headless

- [ ] 1.1 Check whether a `PreCompact` hook with matcher `auto`, given through `--settings`, stops an automatic compaction in `claude -p` when it exits with 2; verify by running a `-p` session with `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` set low and a hook that logs and exits 2, and record the Claude Code version and the result in design.md (fallback in "Risks / Trade-offs").
- [ ] 1.2 Check whether `permissions.defaultMode: auto` from a `--settings` file applies in `claude -p`; verify with a run that edits a file and runs a shell command without prompting, and record the result in design.md.
- [ ] 1.3 Check what `claude -p --session-id <id>` does with an id already in use, and whether `claude -p --resume <id>` finds a session started under another working directory; verify both by hand and record the answers in design.md.
- [ ] 1.4 Check whether a `Read` deny rule on `~/.config/goalner/**` also stops `cat` of that file through Bash in auto mode outside the sandbox; verify by hand and record the result in design.md.

## 2. Data model

- [ ] 2.1 Add migrations for `runners`, `agent_leases` (partial unique index on `agent_id` where `ended_at` is null), `workspaces` (unique `change_id`, state check), `api_tokens.agent_lease_id` with the widened `api_tokens_kind` constraint, `changes.base_branch` (existing rows `main`) and `changes.agent_session_id`, `projects.repository_url` and `projects.default_branch` (default `main`), and `agents.model` and `agents.instructions`; verify that `bin/rails db:migrate` and a rollback succeed, and that the database refuses a second live lease of one agent and a second workspace of one change.
- [ ] 2.2 Add the branch name validator, `Project` repository settings, and `Change#base_branch` with its default from the project and its freeze once a workspace exists (design decision 8); verify with model tests for every scenario of "Repository of a project" and "Base branch of a change".
- [ ] 2.3 Add agent settings (`model`, `instructions`) with their validations; verify with model tests for every scenario of "Agent settings".
- [ ] 2.4 Add `Runner`: creation with a `glnr_runner_` secret stored as a digest, the limit of 10, revocation that ends its leases, and ending every runner of a user when their password changes or is reset (design decision 1); verify with model tests for the scenarios of "Runners" and "List and revoke runners".
- [ ] 2.5 Add `AgentLease`: leasing with its run token, one live lease per agent, replacing the same runner's lease, `agent_leased` and `workspace_elsewhere`, lazy lapse after `AGENT_LEASE_SECONDS`, ending that deletes the run token, and ending on agent deletion (design decision 2); verify with model tests for every scenario of "Lease an agent", "One lease per agent" and "Renewing and ending a lease".
- [ ] 2.6 Leave run tokens out of `Agent#tokens` and the issuing limits, and refuse a run token whose lease is not live in token authentication; verify with tests for "Run tokens", "Run tokens do not count", "Run token left out" and "Run token ends with its lease".
- [ ] 2.7 Add `Workspace`: recording (same values succeed, another path or branch refused), staying on its runner, checkpoints, the states and the list to remove (design decision 3); verify with model tests for every scenario of "Workspace of a change", "Workspace on one machine", "Checkpoints" and "Removing workspaces".
- [ ] 2.8 Extend `ChangeRequest.take!` with the session of a stint (set when an agent comes onto a change, cleared with the agent, filled in when missing) and the workspace filter by the calling lease's runner (design decision 3); verify with model tests for every scenario of "Session of a stint" and the new scenarios of "Take a request", and that the existing take tests still pass.

## 3. API

- [ ] 3.1 Add runner authentication for `/api/runner/` and `GET /api/runner`: runner secrets only, 401 for sessions and API tokens, runner secrets unknown everywhere else, no CSRF, 300 requests a minute and 60 leases an hour, `last_contact_at` to within a minute (design decisions 1 and 4); verify with request tests for every scenario of "Runner authentication" and the new `security-baseline` scenarios.
- [ ] 3.2 Add the lease and release endpoints with the lease response (agent, settings, projects, current change with base branch, session, workspace and taken request); verify with controller tests for every scenario of "Lease an agent" and "One lease per agent", and "Release" of "Renewing and ending a lease".
- [ ] 3.3 Add the workspace endpoints (record, checkpoint and state, list to remove); verify with controller tests for the scenarios of "Workspace of a change", "Workspace on one machine", "Checkpoints" and "Removing workspaces".
- [ ] 3.4 Add the session-only runner endpoints under `/api/me/runners` (list, create with password and lockout, revoke); verify with controller tests for the scenarios of "Runners" and "List and revoke runners", including 403 for any token.
- [ ] 3.5 Create agents without a token or password and with settings, edit settings with `PATCH /api/agents/:id`, and add `lease` to the project's agent list; verify with controller tests for the modified "Create an agent in a project" and "Who can see and handle an agent", "Agent settings" and "Leases in the agent list".
- [ ] 3.6 Accept `base_branch` on change create and update, and add `base_branch` and `workspace` to change lists and the detail, loaded for all listed changes in one query; verify with controller tests for "Base branch of a change" and "Workspace in change responses", and a query-count assertion on the changes list.
- [ ] 3.7 Accept `repository_url` and `default_branch` on project update for the owner only, and return them when reading the project; verify with controller tests for every scenario of "Repository of a project".
- [ ] 3.8 Add `base_branch`, `session_id` and `workspace` to the change of a taken request, and renew the lease of a run token on every take; verify with controller tests for "Base branch, session and workspace" and "Lapse" of "Renewing and ending a lease".
- [ ] 3.9 Filter runner secrets from logs and error reports; verify with a test that a lease request is logged with its `Authorization` header filtered.

## 4. API document and MCP

- [ ] 4.1 Update `docs/openapi.yaml`: agent create without token fields and with settings, `PATCH` agent settings, `lease` on agents, `base_branch` and `workspace` on changes, `base_branch`, `session_id` and `workspace` on taken requests, and `repository_url` and `default_branch` on projects, with no runner endpoints; verify that `bin/openapi-verify` and the examples contract test pass.
- [ ] 4.2 Verify with an MCP test that `claimRequest` with a run token returns the change's base branch, session and workspace, and that the tool list has no runner operation.

## 5. Worker program

- [ ] 5.1 Create `bin/goalner-worker` and `lib/goalner_worker/` with the standard library only, add `goalner_worker` to the `autoload_lib` ignore list, and build the test harness: a stand-in Goalner API in `test/support/` and a stand-in `claude` (through `CLAUDE_BIN`) that records its arguments and environment, writes stream-json, and finishes, fails, hangs or ignores SIGINT as told; verify that an empty worker test runs.
- [ ] 5.2 Add `register` and the configuration file (`$XDG_CONFIG_HOME`, permissions 600 and 700, one entry per address, clones checked) and the refusal of a file readable by others; verify with tests for every scenario of "Register a runner" and "Configuration file safety".
- [ ] 5.3 Add starting by agent id: the arguments, choosing the runner, the local lock, the lease and its refusals, and projects without a clone (design decision 6); verify with tests for every scenario of "Start an agent by its id".
- [ ] 5.4 Add waiting: a round of takes every 10 seconds, the backoff while Goalner is down, and leasing again after 401 at most once in 10 minutes; verify with tests for every scenario of "Waiting for a request", with the waits shortened by environment variables.
- [ ] 5.5 Add attaching: creating or reusing the worktree from the project's clone and the base branch, the refusals, recording the workspace, recreating a missing worktree with the "files lost" note, and the attach hook; verify with tests against a temporary git repository for every scenario of "Attach to a workspace".
- [ ] 5.6 Add running a request: the prompt with the instructions on a session's first run and the notes, `--session-id` or `--resume` chosen by the transcript, the settings, MCP configuration, model and instructions on every run, the environment without the runner secret, the log file and the terminal output (design decision 5); verify with tests for every scenario of "Run a request".
- [ ] 5.7 Write `lib/goalner_worker/instructions.md` for the five kinds of request and the rules of "One request per run"; verify by review against the requirement, and with a test that the first run's prompt holds it and a resumed run's prompt doesn't.
- [ ] 5.8 Add the heartbeat during a run and stopping it (same request, none, another, 401 with a new lease; interrupt, terminate, kill); verify with tests for every scenario of "Heartbeat and stopping a run".
- [ ] 5.9 Add what happens after a run: the checkpoint, resuming after 1, 5 and 15 minutes, and failing after the third unfinished run; verify with tests for every scenario of "After a run".
- [ ] 5.10 Add stopping and restarting: releasing on SIGINT and SIGTERM, and stopping a run left by a killed worker from the state directory (design decision 6); verify with tests for every scenario of "Stop and restart the worker".
- [ ] 5.11 Add removing finished workspaces at start and after an archive request: the detach hook, removing without forcing, kept and removed; verify with tests for every scenario of "Remove finished workspaces".
- [ ] 5.12 Add `.claude/goalner-worker.settings.json` with the permission mode, the deny rule and the `PreCompact` hook through `GOALNER_WORKER_HOME`, adjusted to the spike results; verify that `test/bin/goalner_context_full_test.rb` passes with a run token, and with a test for "Context fills during a step" against the stand-ins.
- [ ] 5.13 Add `bin/goalner-attach` and `bin/goalner-detach` (design decision 7); verify by running them in a temporary worktree with `GOALNER_TEST_DB_SUFFIX=c0`, checking that the test databases are created and then dropped and that the development database's schema version is unchanged.

## 6. Web client

- [ ] 6.1 Types and API calls for runners, leases, agent settings, base branches, workspaces and the project repository; verify that `npm run typecheck` passes.
- [ ] 6.2 Add the Runners screen and the warning on the password change form; verify with system tests for every scenario of "Runners screen" and "Runners entry".
- [ ] 6.3 Change the Agents screen: create without a token with optional settings and the start hint, edit settings, where each agent runs, and issuing tokens with a password; verify with system tests for every scenario of the modified "Agents screen".
- [ ] 6.4 Add the base branch to the New change dialog; verify with a system test for "Base branch".
- [ ] 6.5 Add the base branch and the workspace to the change page; verify with system tests for every scenario of "Workspace on the change page".
- [ ] 6.6 Add the repository to the project settings; verify with a system test for "Set the default branch".
- [ ] 6.7 English and Russian texts; verify that `npm test`, `npm run typecheck` and `npm run policy` pass, and that `bin/rails test:system` passes after `npx vite build --mode test`.

## 7. Workflow and docs

- [ ] 7.1 Remove `.claude/skills/goalner-worker/`, and rewrite the README's "Running agents": creating a runner, registering each machine as its own runner, creating agents, `bin/goalner-worker <id>` from a checkout of `main`, the subscription login and `ANTHROPIC_API_KEY`, and the migration steps; verify that no file in the repository still mentions `/loop /goalner-worker`.

## 8. End to end

- [ ] 8.1 Follow design.md's "Migration Plan" on this machine with Fish and Heron on TEST, then run a test change through every step. Verify:
  - "Start exploring" creates the workspace and its session;
  - Ctrl-C during a step, then `bin/goalner-worker <id>`, resumes the same session;
  - releasing Fish gives Heron the same workspace with a new session;
  - archiving removes the workspace.

  Record what happened in this task.
- [ ] 8.2 Fill a run's context on purpose during an implement step; verify that the change is blocked, the compaction doesn't run and the worker stops the run, or that the fallback chosen in task 1.1 does the same.
- [ ] 8.3 Run the whole test suite, `bin/rubocop`, `bin/brakeman` and `bin/openapi-verify`; verify that all pass.
