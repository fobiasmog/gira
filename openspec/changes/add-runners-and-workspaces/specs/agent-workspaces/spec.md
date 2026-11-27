## Purpose

Gives each change a workspace on one machine, and gives each agent's stint on the change a session, so that any agent and any worker can continue a change from the same files and the same conversation after a release, a pause, a crash or a restart.

## ADDED Requirements

### Requirement: Workspace of a change
A change SHALL have at most one workspace. A runner (spec `agent-runners`) SHALL be able to record the workspace of an open change while it holds a live lease of the agent that is on the change, by giving its path, a text of 1 to 1,000 characters, and its branch. Goalner SHALL record the runner, the path, the branch, the change's base branch at that moment (spec `changes`, "Base branch of a change") and when it was recorded, and the workspace SHALL be active. Recording the same path and branch again SHALL succeed and change nothing. Recording another path or branch for a change whose workspace is active SHALL be refused with a validation error and SHALL change nothing. A runner without such a lease SHALL receive HTTP 404. The workspace SHALL stay with the change when its agent is released and when another agent comes onto it.

#### Scenario: Record
- **WHEN** Fish is on `export-csv` with a live lease of Bob's runner "laptop", and "laptop" records the workspace of `export-csv` at `/home/bob/goalner/workspaces/TEST/export-csv` on the branch `export-csv`
- **THEN** `export-csv` has an active workspace on "laptop" with that path and branch, and with the base branch `main`

#### Scenario: Recorded again
- **WHEN** "laptop" records the same path and branch for `export-csv` a second time
- **THEN** the request succeeds, and the workspace is unchanged

#### Scenario: Another path
- **WHEN** `export-csv` has an active workspace at one path, and "laptop" records another path for it
- **THEN** the request is rejected with a validation error, and the workspace keeps its path

#### Scenario: No lease
- **WHEN** "laptop" holds no lease of the agent on `export-csv`, and records a workspace for it
- **THEN** the response is HTTP 404, and no workspace is recorded

#### Scenario: Released agent
- **WHEN** a member releases Fish from `export-csv`, and agent Heron then takes its next request
- **THEN** `export-csv` keeps its workspace on "laptop", and Heron is given that workspace

### Requirement: Workspace on one machine
A workspace SHALL stay on the runner that recorded it for as long as it exists. Only that runner SHALL be able to report on it or change its state. Any other runner SHALL receive HTTP 404 for it. Takes (spec `change-requests`, "Take a request") and leases (spec `agent-runners`, "One lease per agent") SHALL keep a change whose workspace is active away from other runners.

#### Scenario: Other runner
- **WHEN** Bob's runner "desktop" reports a checkpoint for the workspace of `export-csv`, which "laptop" recorded
- **THEN** the response is HTTP 404, and the workspace is unchanged

### Requirement: Session of a stint
When an agent comes onto a change (spec `change-requests`, "Agent of a change"), Goalner SHALL give that stint a new session id, a random version 4 UUID, before it returns the request. The session id SHALL stay the same for every request of the stint, and SHALL end with the stint, when the agent is released or the change is archived. The next stint on the change SHALL get a new session id. An agent that is on a change without a session id SHALL get one on its next take or lease.

#### Scenario: First take
- **WHEN** Fish takes the explore request of `export-csv`, which has no agent
- **THEN** the returned request names a session id for Fish's stint on `export-csv`

#### Scenario: Later request of the stint
- **WHEN** Fish, still on `export-csv`, later takes its reply request
- **THEN** the returned request names the same session id

#### Scenario: New stint
- **WHEN** a member releases Fish from `export-csv`, and Heron takes its next request
- **THEN** the returned request names a session id other than Fish's

### Requirement: Checkpoints
The runner of an active workspace SHALL be able to report a checkpoint: the commit its branch is at, as 40 hexadecimal characters, and whether the worktree holds uncommitted changes. Goalner SHALL keep the latest checkpoint with the time it was reported. A malformed commit SHALL be refused with a validation error.

#### Scenario: Report
- **WHEN** "laptop" reports that the workspace of `export-csv` is at commit `a1b2c3…` with uncommitted changes
- **THEN** opening `export-csv` shows that commit, that changes are uncommitted, and when it was reported

### Requirement: Workspace in change responses
Change lists and opening a change (spec `changes`), taken requests (spec `change-requests`, "Take a request") and leases (spec `agent-runners`, "Lease an agent") SHALL include the change's workspace: the name of its runner, its path, branch and base branch, its state (active, kept or removed), and its latest checkpoint with its time, or `null` when no checkpoint was reported. A change that never had a workspace SHALL show `null`.

#### Scenario: Open a change with a workspace
- **WHEN** a member opens `export-csv`, whose workspace is active on "laptop"
- **THEN** the response names "laptop", the workspace's path, its branch `export-csv`, its base branch `main`, the state active and its latest checkpoint

#### Scenario: No workspace
- **WHEN** a member opens `add-tags`, which is in Idea
- **THEN** its workspace is `null`

### Requirement: Removing workspaces
A runner SHALL be able to list its workspaces that are active or kept and whose changes are archived. It SHALL be able to mark such a workspace as removed, or as kept when the worktree could not be removed because it holds uncommitted changes. A removed workspace SHALL NOT become active or kept again. A kept workspace SHALL stay in the list until it is marked as removed. A workspace of an open change SHALL NOT be marked as removed or kept, which SHALL be refused with a validation error.

#### Scenario: To remove
- **WHEN** `export-csv` was archived with an active workspace on "laptop", and "laptop" lists its workspaces to remove
- **THEN** the list holds the workspace of `export-csv`

#### Scenario: Removed
- **WHEN** "laptop" marks that workspace as removed
- **THEN** opening `export-csv` shows the workspace as removed, and it is no longer listed for removal

#### Scenario: Kept
- **WHEN** "laptop" marks that workspace as kept
- **THEN** opening `export-csv` shows it as kept, and it is still listed for removal

#### Scenario: Open change
- **WHEN** "laptop" marks the workspace of the open change `add-tags` as removed
- **THEN** the request is rejected with a validation error, and the workspace stays active
