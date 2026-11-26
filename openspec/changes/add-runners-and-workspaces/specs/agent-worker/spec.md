## Purpose

Defines `bin/goalner-worker`, the program that runs any agent by its id on a machine registered as a runner: it leases the agent, attaches to the workspace of the agent's change, runs each request as one headless Claude Code run, and continues the same request in the same session after any interruption.

## ADDED Requirements

### Requirement: Register a runner
`bin/goalner-worker register --url <Goalner address> --token <runner secret>` SHALL check the secret with Goalner (spec `agent-runners`, "Runner authentication"), then save the runner in the configuration file and print the runner's name. Options SHALL set the runner's workspaces root (`--workspaces <directory>`, by default `~/goalner/workspaces`) and the local clone of a project's repository (`--clone <project short name>=<path>`, repeatable). The configuration file SHALL be `goalner/runners.yml` in `$XDG_CONFIG_HOME`, or in `~/.config` when that is not set. It SHALL hold a list of runners, one per Goalner address. Registering SHALL replace the entry with the same address and keep the others. The worker SHALL create the file with permissions 600 and its directory with permissions 700. A secret that Goalner rejects, or a clone path that is not a git working copy, SHALL end the command with exit status 1 and an explanation, writing nothing.

#### Scenario: Register
- **WHEN** a user runs `bin/goalner-worker register --url http://localhost:3000 --token glnr_runner_… --clone TEST=~/dev/goalner`
- **THEN** the command prints the runner's name, and `runners.yml` holds one runner for `http://localhost:3000` with that secret, the default workspaces root and the clone of TEST, readable and writable only by the user

#### Scenario: A second Goalner
- **WHEN** the user then registers a runner for `https://goalner.com`
- **THEN** `runners.yml` holds both runners

#### Scenario: Rejected secret
- **WHEN** the user registers with a secret that Goalner rejects
- **THEN** the command ends with exit status 1, says that Goalner rejected the secret, and `runners.yml` is unchanged

### Requirement: Configuration file safety
The worker SHALL refuse to run when its configuration file can be read or written by other users of the machine, naming the file and the command that fixes its permissions. The worker SHALL never print a runner secret or a run token, and SHALL never put a runner secret into the environment of a process it starts.

#### Scenario: Readable by others
- **WHEN** `runners.yml` has permissions 644, and the user starts the worker
- **THEN** the worker ends with exit status 1, naming the file and `chmod 600`

### Requirement: Start an agent by its id
`bin/goalner-worker <agent id>` SHALL run the agent with that id through the runner of the configuration file, or through the runner for `--url <Goalner address>` when several are configured. It SHALL lease the agent (spec `agent-runners`, "Lease an agent") before doing anything else. The worker SHALL end with exit status 1 and a message, without leasing, when no agent id is given, saying that agents are created in Goalner first and how to start one; when no runner is configured; when several runners are configured and `--url` names none of them. It SHALL end with exit status 1 and a message when the lease is refused:
- for an agent that does not exist or that the runner's owner cannot see;
- for an agent leased to another runner, naming that runner and since when;
- for an agent whose change has its workspace on another runner, naming that runner.

It SHALL also end with exit status 1 when none of the projects the lease names has a clone in the configuration, naming those projects. It SHALL refuse to start, with exit status 1 and before leasing, while another worker on the same machine runs the same agent through the same runner.

#### Scenario: No agent id
- **WHEN** a user runs `bin/goalner-worker` without an agent id
- **THEN** the worker ends with exit status 1 and says to create the agent in Goalner first and to start it with `bin/goalner-worker <agent id>`

#### Scenario: Leased elsewhere
- **WHEN** Fish has a live lease of the runner "desktop", and the user starts `bin/goalner-worker 6` on "laptop"
- **THEN** the worker ends with exit status 1 and says that Fish is running on "desktop" and since when

#### Scenario: No clone
- **WHEN** Fish belongs only to OPS, and the configuration has no clone for OPS
- **THEN** the worker ends with exit status 1, names OPS, and releases the lease

#### Scenario: Started twice on one machine
- **WHEN** `bin/goalner-worker 6` is running, and the user starts `bin/goalner-worker 6` again on the same machine
- **THEN** the second worker ends with exit status 1, saying that Fish already runs here, and the first worker keeps its lease

### Requirement: Waiting for a request
While no run is in progress, the worker SHALL take a request (spec `change-requests`, "Take a request") with the run token in each of the agent's projects that has a clone, one round every 10 seconds, and SHALL start no Claude Code process. When Goalner cannot be reached or answers with a server error, the worker SHALL say so once, wait 10 seconds and double the wait up to 60 seconds, and say when Goalner answers again. When the run token receives HTTP 401, the worker SHALL lease the agent again, at most once in 10 minutes, and SHALL end with exit status 1 and the reason when it cannot.

#### Scenario: Nothing to do
- **WHEN** Fish's worker has taken no request for an hour
- **THEN** no Claude Code process has run, and Fish is listed as online

#### Scenario: Goalner down
- **WHEN** Goalner stops answering for two minutes while Fish's worker waits
- **THEN** the worker says once that Goalner cannot be reached, keeps trying at most every 60 seconds, and says when it answers again

#### Scenario: Lease lapsed while asleep
- **WHEN** the machine sleeps for ten minutes, so Fish's lease lapses, and then wakes
- **THEN** the worker leases Fish again and carries on

### Requirement: Attach to a workspace
When a request arrives, the worker SHALL settle the workspace of its change (spec `agent-workspaces`) before running anything:
- when the change has no workspace, its path SHALL be `<workspaces root>/<project short name>/<change name>` and its branch the change's name. The worker SHALL create a git worktree there from the project's clone: on a new branch cut from the change's base branch, or on the existing branch when the path already holds a worktree of it. It SHALL then record the workspace in Goalner;
- when the change has an active workspace, the worker SHALL use its path. When the path is missing and its branch exists, it SHALL create the worktree there again and add the "files lost" note to the run (requirement "Run a request").

The worker SHALL finish the request as failed (spec `change-requests`, "Finish a request"), with a comment that names the problem, when the branch already exists but the path holds no worktree of it, when the path exists but is not a worktree of that branch, when the base branch does not exist in the clone, or when the branch of an active workspace no longer exists. It SHALL then run the repository's attach hook, `bin/goalner-attach` in the workspace, when that file exists and is executable, with the run's environment (requirement "Run a request"). When the hook exits with a status other than 0, the worker SHALL finish the request as failed with the last 2,000 characters of its output.

#### Scenario: First request of a change
- **WHEN** Fish takes the explore request of `export-csv` in TEST, whose base branch is `main` and which has no workspace
- **THEN** a worktree of the TEST clone exists at `<workspaces root>/TEST/export-csv` on a new branch `export-csv` cut from `main`, Goalner records it as the workspace of `export-csv`, and the attach hook has run there

#### Scenario: After a crash before recording
- **WHEN** the worker created the worktree of `export-csv` and was killed before recording it, and Fish's next worker takes the same request
- **THEN** the worker uses the existing worktree, records the workspace, and runs the request

#### Scenario: Branch taken
- **WHEN** a branch `export-csv` already exists in the clone, and no worktree of it is at the workspace path
- **THEN** the request is finished as failed with a comment naming the branch, and no worktree is created

#### Scenario: Attach hook fails
- **WHEN** the attach hook exits with status 1
- **THEN** the request is finished as failed with the end of the hook's output, and no Claude Code process is started

### Requirement: Run a request
Each request SHALL be one run of `claude -p` in the workspace:
- its prompt SHALL hold the request as JSON. On the first run of a session it SHALL also hold the worker's instructions for requests (requirement "One request per run"). It SHALL end with any notes: that the previous run was interrupted, or that the workspace's files or the session's context were lost;
- it SHALL continue the session of the agent's stint (spec `agent-workspaces`, "Session of a stint") with `--resume <session id>` when a transcript of that session exists under `~/.claude/projects/`, and otherwise create it with `--session-id <session id>`. When the stint had earlier runs and no transcript exists, the "context lost" note SHALL be added;
- it SHALL get, on every run, the MCP configuration `.claude/goalner-worker.mcp.json` and the settings `.claude/goalner-worker.settings.json` of the worker's own checkout with `--strict-mcp-config`, and the agent's model and instructions when they are set;
- its environment SHALL be the worker's, with `GOALNER_TOKEN` set to the run token, `GOALNER_URL` and `GOALNER_MCP_URL` to the runner's Goalner, `GOALNER_WORKER_HOME` to the worker's checkout, and `GOALNER_TEST_DB_SUFFIX` to `c` followed by the change's id.

The worker SHALL save each run's full output under `log/agents/<agent id>/<request id>.jsonl` in its checkout. It SHALL show in the terminal a line with the time for each of its own events, the run's text, one short line for each tool call, and the run's duration and cost at its end.

#### Scenario: First run of a stint
- **WHEN** Fish's worker runs the explore request of `export-csv`, and no transcript of the stint's session exists
- **THEN** `claude -p` is started in the workspace with `--session-id` and the stint's session id, and its prompt holds the worker's instructions and the request

#### Scenario: Later run of the stint
- **WHEN** Fish's worker runs the reply request of `export-csv`, and the transcript of the stint's session exists
- **THEN** `claude -p` is started with `--resume` and the same session id, and with the same MCP configuration and settings as the first run

#### Scenario: No runner secret in the run
- **WHEN** a run starts
- **THEN** its environment holds the run token as `GOALNER_TOKEN` and no runner secret

#### Scenario: Model
- **WHEN** Fish's model is `opus`
- **THEN** every run of Fish's worker is started with `--model opus`

### Requirement: One request per run
The worker's instructions SHALL tell the agent to do the step that the request's kind asks for on its change (explore, propose, reply, implement or archive) in the workspace. They SHALL tell it to commit only on the change's branch and never to push, open pull requests or merge. They SHALL tell it to finish the request with `finishRequest` and one comment, and to end its turn after finishing. They SHALL also tell it never to take another request, and to stop without finishing when it is told that its context is full and its change is blocked. The worker SHALL never finish a request that its run finished.

#### Scenario: Finished by the run
- **WHEN** a run finishes the explore request of `export-csv` with its questions and ends
- **THEN** the request is done with the run's comment, and the worker posts nothing on `export-csv`

### Requirement: Heartbeat and stopping a run
While a run is in progress, the worker SHALL take a request in the change's project every 30 seconds:
- when the take returns the same request, the run SHALL go on;
- when it returns no request, because the request was cancelled, the agent was released or the change is blocked, the worker SHALL stop the run;
- when it returns another request, the worker SHALL stop the run and then run that request.

When the take is answered with HTTP 401, because the lease ended, the worker SHALL lease the agent again as in requirement "Waiting for a request", stop the run, and continue the request in the same session with the new run token and the "interrupted" note. When the take fails in any other way, the run SHALL go on. To stop a run, the worker SHALL interrupt it, terminate its process group if it is still running 30 seconds later, and kill the process group 10 seconds after that.

#### Scenario: Cancelled
- **WHEN** a member cancels the implement request that Fish's run is working on
- **THEN** within 30 seconds the worker stops the run and waits for the next request

#### Scenario: Released
- **WHEN** a member releases Fish from `export-csv` during a run
- **THEN** within 30 seconds the worker stops the run, and the workspace of `export-csv` stays as it is

#### Scenario: Lease lapsed during a run
- **WHEN** Goalner could not be reached for six minutes during a run, so Fish's lease lapsed, and Goalner then answers the heartbeat with HTTP 401
- **THEN** the worker leases Fish again, stops the run, and resumes the same session with the new run token and the "interrupted" note

#### Scenario: Process ignores the interrupt
- **WHEN** a stopped run is still running 30 seconds after the interrupt
- **THEN** the worker terminates its process group, and kills it 10 seconds later if it is still running

### Requirement: After a run
When a run ends, the worker SHALL report a checkpoint of the workspace (spec `agent-workspaces`, "Checkpoints"). It SHALL then take a request. When the take returns the same request, the run ended without finishing it. The worker SHALL then continue the same session with the "interrupted" note after waiting 1, 5 and 15 minutes in turn, taking requests meanwhile as its heartbeat. After a third run in a row that leaves the request unfinished, it SHALL finish the request as failed, quoting at most 2,000 characters of what the last run reported. The count SHALL start again for each request.

#### Scenario: Dropped connection
- **WHEN** a run of the implement request of `export-csv` ends with a connection error, and the request is still taken by Fish
- **THEN** the worker reports a checkpoint, and a minute later resumes the same session with the "interrupted" note

#### Scenario: Three times
- **WHEN** three runs in a row leave the same request unfinished
- **THEN** the worker finishes the request as failed, quoting what the last run reported

### Requirement: Full context during a run
The settings of every run SHALL hold a `PreCompact` hook for automatic compaction that runs `bin/goalner-context-full` of the worker's checkout with the run token. When Goalner answers that the agent is blocked (spec `change-requests`, "Full context"), the hook SHALL stop the compaction, and the worker's next take SHALL return no request, so the worker stops the run (requirement "Heartbeat and stopping a run").

#### Scenario: Context fills during a step
- **WHEN** a run's context fills up while Fish works on the implement request of `export-csv`
- **THEN** `export-csv` is blocked, the compaction does not run, the worker stops the run, and the implement request stays taken by Fish

### Requirement: Stop and restart the worker
On an interrupt from the terminal or a termination signal, the worker SHALL stop the run as in requirement "Heartbeat and stopping a run", release the lease, and exit with status 0. The request SHALL stay taken. When the worker starts again for the same agent, the lease SHALL name that request, and the worker SHALL continue it in the same session with the "interrupted" note. A worker that was killed without releasing its lease SHALL be able to start again at once on the same runner (spec `agent-runners`, "One lease per agent"). When a run started by a killed worker is still running, the new worker SHALL stop it before it runs anything, so that two runs never continue one session at once.

#### Scenario: Ctrl-C and start again
- **WHEN** a user presses Ctrl-C while Fish's run works on the implement request of `export-csv`, and later runs `bin/goalner-worker 6` again
- **THEN** the first worker released its lease and exited with status 0, and the new worker resumes the same session on the implement request with the "interrupted" note

#### Scenario: Killed
- **WHEN** Fish's worker is killed, and the user starts `bin/goalner-worker 6` again a minute later on the same runner
- **THEN** the new worker leases Fish and continues the taken request

#### Scenario: Orphaned run
- **WHEN** Fish's worker was killed while its run kept going, and the user starts `bin/goalner-worker 6` again
- **THEN** the new worker stops the old run before resuming the session

### Requirement: Remove finished workspaces
When it starts, and after a run finishes an archive request as done, the worker SHALL list its runner's workspaces to remove (spec `agent-workspaces`, "Removing workspaces"). For each one, it SHALL run the repository's detach hook, `bin/goalner-detach` in the workspace, when it exists and is executable. It SHALL then remove the worktree without forcing and mark the workspace as removed. When the worktree holds uncommitted changes, it SHALL leave it in place and mark the workspace as kept. When the path no longer exists, it SHALL mark the workspace as removed. The branch SHALL stay.

#### Scenario: Archived change
- **WHEN** Fish finishes the archive request of `export-csv` as done, and its worktree holds no uncommitted changes
- **THEN** the detach hook has run, the worktree is gone, the branch `export-csv` still exists, and the workspace is removed

#### Scenario: Uncommitted changes
- **WHEN** the worktree of the archived change `fix-login` holds an uncommitted file
- **THEN** the worktree stays in place, and the workspace of `fix-login` is kept

### Requirement: Goalner's workspace hooks
Goalner's repository SHALL provide `bin/goalner-attach`, which installs the gems and JavaScript packages the workspace needs and prepares the test databases named by `GOALNER_TEST_DB_SUFFIX`. It SHALL also provide `bin/goalner-detach`, which drops those test databases. Neither SHALL create, migrate or drop the development database, and both SHALL be safe to run more than once.

#### Scenario: Attach leaves development alone
- **WHEN** the attach hook runs in the workspace of a change whose branch adds a migration
- **THEN** the change's test databases have that migration, and the development database does not
