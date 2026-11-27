## MODIFIED Requirements

### Requirement: Screens
The client SHALL provide screens for:
- a personal dashboard (own or a teammate's open tasks and upcoming deadlines);
- the project list and project creation;
- a project's board, one change at a time, in the kanban layout; the list layout is reached only by its address, since the board offers no layout switch for now, and tasks are added from their column's own add action;
- task details;
- changes, and each change's page;
- members and invitations;
- agents;
- project settings (owner only);
- the project archive and an archived task;
- profile settings (name, language, contact links, avatar, password, API tokens, runners, connected apps);
- announcements;
- feedback.

#### Scenario: Board screen
- **WHEN** a member opens a project's board
- **THEN** the project's columns are shown in order with their tasks, each card showing key, title, label, assignee avatar, deadline and importance, and no switch to another layout is offered

#### Scenario: Owner-only settings
- **WHEN** a non-owner member opens the project
- **THEN** no project settings entry is offered

#### Scenario: Agents entry
- **WHEN** any member opens a project
- **THEN** the project's sections include Agents

#### Scenario: No sprints, backlog or milestones
- **WHEN** any member opens a project
- **THEN** the project's sections include Changes, and include no Backlog, Sprints or Milestones

#### Scenario: Runners entry
- **WHEN** a signed-in user opens their settings
- **THEN** the settings include Runners

### Requirement: Agents screen
Each project SHALL have an Agents screen. It SHALL list the project's agents with their name, address, creator, number of live tokens, whether they are online or offline with their last check-in, and the change each one is on (spec `change-requests`, "Check-ins"), and where each one runs: the runner, its owner and since when, or that it is not running (spec `agent-runners`, "Leases in the agent list"), and its deleted agents in a collapsed group. From it, a member SHALL be able to:
- create an agent from a name and, optionally, a model and instructions (spec `agents`, "Agent settings"), without a token or a password;
- add an agent they can see from another of their projects;
- edit an agent's name, model and instructions;
- remove an agent from the project, except from its last project;
- delete an agent, after confirming;
- restore a deleted agent;
- list an agent's tokens with issuer, access, channels, last four characters, creation time and last use;
- issue a token from a name, read-only or read-write access, its channels (API, MCP or both) and the current password;
- revoke a token, after confirming.

A new token's value SHALL be shown once, with a copy control and a warning that it will not be shown again. When the token includes MCP, the screen SHALL also show a ready-to-copy MCP client configuration with the MCP endpoint and the value, a note that a client configured with it in a working copy acts as that agent there, and a link to the MCP guide. When it includes the API, the screen SHALL link to the API documentation. After an agent is created, and on request for any active agent, the screen SHALL show the command that starts it, with a copy control: `bin/goalner-worker` and the agent's name, or its id when another agent of the project has the same name. A name that needs quoting in a shell SHALL be quoted.

#### Scenario: Create
- **WHEN** a member creates agent "Fish" with the model `opus`
- **THEN** Fish appears in the list as not running, no token is shown, and the screen shows how to start Fish with `bin/goalner-worker Fish`

#### Scenario: Create with MCP
- **WHEN** a member creates agent "Fish", then issues it an MCP-only token with their correct password
- **THEN** creating showed no token, and issuing shows the token's value once with a copy control, a warning and an MCP client configuration containing it

#### Scenario: Agent states
- **WHEN** Fish checked in a minute ago and is on `export-csv`, and Owl last checked in two hours ago
- **THEN** the list shows Fish as online and on `export-csv`, and Owl as offline with its last check-in

#### Scenario: Start command
- **WHEN** a member chooses the start command of agent "Code Reviewer"
- **THEN** the screen shows `bin/goalner-worker 'Code Reviewer'` with a copy control

#### Scenario: Where an agent runs
- **WHEN** Fish has a live lease of Bob's runner "laptop", started at 14:05
- **THEN** the list shows that Fish runs on "laptop" of Bob since 14:05

#### Scenario: Wrong password
- **WHEN** a member submits the token form with a wrong current password
- **THEN** the error is shown under the password field and the other fields keep their values

#### Scenario: Only project
- **WHEN** a member opens the actions of an agent that belongs to no other non-archived project
- **THEN** removing it from the project is not offered, and deleting it is

#### Scenario: Restore
- **WHEN** a member restores a deleted agent from the deleted group
- **THEN** the agent moves to the list of agents, with no tokens

## ADDED Requirements

### Requirement: Runners screen
The settings SHALL include a Runners screen that lists the user's runners (spec `agent-runners`, "List, rotate and revoke runners"), each with its name, the last four characters of its secret, when it was created, its last contact and the agents it runs now. It SHALL create a runner from a name and the current password. A new runner's secret SHALL be shown once, with a copy control, a warning that it will not be shown again, and the ready-to-copy command `bin/goalner-worker register --url <this Goalner> --token <secret>`. Rotating a runner's secret SHALL ask for the current password, saying which agents it stops, and SHALL then show the new secret as for a new runner. Revoking a runner SHALL ask for confirmation, saying which agents it stops.

#### Scenario: Create and copy
- **WHEN** a user creates the runner "laptop" with their correct password
- **THEN** the secret is shown once with a copy control, a warning and the register command containing it, and "laptop" appears in the list

#### Scenario: Wrong password
- **WHEN** a user submits the runner form with a wrong current password
- **THEN** the error is shown under the password field and the name keeps its value

#### Scenario: Rotate a running runner's secret
- **WHEN** a user chooses to rotate the secret of "laptop", which runs Fish, and enters their correct password
- **THEN** the dialog said that Fish will stop, and the new secret is shown once with a copy control, a warning and the register command containing it

#### Scenario: Revoke a running runner
- **WHEN** a user chooses to revoke "laptop", which runs Fish
- **THEN** the confirmation says that Fish will stop, and after confirming "laptop" disappears from the list

### Requirement: Workspace on the change page
The change page (requirement "Change page") SHALL show the change's base branch (spec `changes`, "Base branch of a change"). When the change has a workspace (spec `agent-workspaces`), the page SHALL show its runner, its path with a copy control, its branch, its state, and its latest checkpoint: the commit's first seven characters, whether changes are uncommitted, and when it was reported. A kept workspace SHALL be marked as kept because of uncommitted changes.

#### Scenario: Workspace shown
- **WHEN** a member opens the page of `export-csv`, whose workspace is active on "laptop" at commit `a1b2c3d…` with uncommitted changes
- **THEN** the page shows "laptop", the workspace's path with a copy control, the branch `export-csv`, the base branch `main`, the commit `a1b2c3d`, and that changes are uncommitted

#### Scenario: Base branch before work starts
- **WHEN** a member opens the page of `add-tags`, which is in Idea and has no workspace
- **THEN** the page shows the base branch `main` without an edit action, and no workspace
