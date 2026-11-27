## Why

To start an agent today, a person copies its token when creating it and pastes it into a Claude Code session. Stopping and starting again means finding that token, or issuing another one. An agent's work also lives in that one session and its worktree, so a dropped connection, a reboot or a closed terminal leaves the person to piece the work back together. Agents should be started from their id alone, and should continue from the same conversation and files whatever interrupted them.

## What Changes

- **Runners.** A person creates a runner in Goalner, which shows its secret once, and registers it on a machine once. A runner proves who the machine is, as GitLab runners do. It can lease the agents its owner can see and nothing else, and it never acts as its owner.
- **Leases and run tokens.** Starting an agent leases it to a runner. Goalner then mints a run token for the agent, an agent token that nobody sees and that ends with the lease. An agent has at most one lease, so only one worker runs it. A lease lapses when its worker stops claiming.
- **Workspaces.** Each change owns a workspace on one machine: a git worktree at a fixed path, its own test databases, and the Claude Code sessions of the agents that work on it. Goalner records where the workspace is, which session belongs to the agent's current stint on the change, and the last commit the worker reported. Any agent and any worker continue from it. A released change keeps its workspace, and an archived change's workspace is removed.
- **The worker.** `bin/goalner-worker <agent id>` replaces the `/loop` workflow. It holds no identity of its own: it leases the agent, asks Goalner for the agent's work, attaches to the change's workspace, and runs each request as one headless `claude -p`. The first run of a stint creates its session with `--session-id`, and later runs continue it with `--resume`. No Claude process runs while the agent waits. After a pause, a dropped connection, a crash or a restart, the worker continues the same request in the same session.
- **Agent settings.** An agent gets an optional model and instructions, which the worker passes to every run. Creating an agent no longer issues a token or asks for a password.
- **Base branch.** Each change records the branch its work starts from, which is `main` for now. Choosing another base branch is postponed.
- **Takes respect workspaces.** A request of a change whose workspace is on a runner goes only to that runner's run tokens. A taken request names its change's base branch, workspace and session.
- **Screens.** The settings get a Runners screen. The Agents screen creates agents without tokens, edits their model and instructions, and shows where each agent runs. The change page shows the change's workspace and base branch.
- **BREAKING (workflow):** the `goalner-worker` skill and its `/loop` workflow are removed, and the README's "Running agents" is rewritten around runners and `bin/goalner-worker`. Agents already working through `/loop` have to be stopped first (see design.md, "Migration Plan").

Not included:
- starting or stopping workers from the app;
- moving a workspace to another machine, pushing branches, or keeping transcripts in Goalner;
- workers in VMs, or isolating agents from the runner secret with a separate OS user;
- choosing a change's base branch, and a project's repository address and default branch;
- more than one repository per project.

## Capabilities

### New Capabilities

- `agent-runners`: runners and their secrets, leasing an agent to a runner, run tokens, and how leases end.
- `agent-workspaces`: the workspace of a change, the session of an agent's stint on it, checkpoints, and removing workspaces of archived changes.
- `agent-worker`: the `bin/goalner-worker` program: registering a runner, starting an agent by its id, attaching to workspaces, running requests headless, continuing after interruptions, and cleaning up.

### Modified Capabilities

- `agents`: agents get a model and instructions; creating one issues no token and needs no password; run tokens are left out of token lists, limits and the 100-year lifetime.
- `change-requests`: a take made with a run token, or any other, skips requests of changes whose workspace is on another runner; a taken request names its change's base branch, workspace and session.
- `changes`: a change has a base branch, which is `main` for now.
- `security-baseline`: runner endpoints accept runner tokens, which are the only endpoints that do, and need no CSRF token.
- `web-client`: Runners screen; agents created without tokens and with settings, and where they run; the workspace and the base branch on the change page.

## Impact

- Database: new tables `runners`, `agent_leases` and `workspaces`; new columns `agents.model` and `agents.instructions`, `changes.base_branch` and `changes.agent_session_id`, and `api_tokens.agent_lease_id`, which widens the `api_tokens_kind` constraint.
- API: runner endpoints under `/api/runner`, authenticated by runner tokens and left out of the OpenAPI document and the MCP tools. New fields in change, take, agent and project responses, which the API document and its verification cover.
- Web client: settings, Agents screen, change page.
- Repository: `bin/goalner-worker` in Ruby with the standard library only; `bin/goalner-attach` and `bin/goalner-detach` as Goalner's own workspace hooks; `.claude/goalner-worker.settings.json`, beside the existing `.claude/goalner-worker.mcp.json`; `.claude/skills/goalner-worker/` removed; README rewritten.
- Claude Code: needs a version whose headless mode supports `--session-id`, `--resume`, `--settings`, `--strict-mcp-config` and `stream-json` output. The spike tasks record the version tested.
