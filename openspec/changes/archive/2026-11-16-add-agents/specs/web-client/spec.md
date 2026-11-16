## ADDED Requirements

### Requirement: Agents screen
Each project SHALL have an Agents screen. It SHALL list the project's agents with their name, address, creator and number of live tokens, and its deleted agents in a collapsed group. From it, a member SHALL be able to:
- create an agent from a name, the first token's name, read-only or read-write access, its channels (API, MCP or both) and the current password;
- add an agent they can see from another of their projects;
- rename an agent;
- remove an agent from the project, except from its last project;
- delete an agent, after confirming;
- restore a deleted agent;
- list an agent's tokens with issuer, access, channels, last four characters, creation time and last use;
- issue a token with the same fields as at creation;
- revoke a token, after confirming.

A new token's value SHALL be shown once, with a copy control and a warning that it will not be shown again. When the token includes MCP, the screen SHALL also show a ready-to-copy MCP client configuration with the MCP endpoint and the value, and a link to the MCP guide. When it includes the API, the screen SHALL link to the API documentation.

#### Scenario: Create with MCP
- **WHEN** a member creates agent "Fish" with an MCP-only token and their correct password
- **THEN** the token's value is shown once with a copy control, a warning and an MCP client configuration containing it, and Fish appears in the list

#### Scenario: Wrong password
- **WHEN** a member submits the creation form with a wrong current password
- **THEN** the error is shown under the password field and the other fields keep their values

#### Scenario: Only project
- **WHEN** a member opens the actions of an agent that belongs to no other non-archived project
- **THEN** removing it from the project is not offered, and deleting it is

#### Scenario: Restore
- **WHEN** a member restores a deleted agent from the deleted group
- **THEN** the agent moves to the list of agents, with no tokens

### Requirement: Agent marker
Wherever the client shows a user, an agent SHALL carry a visible marker with an accessible name, and a deleted agent SHALL additionally be marked as deleted. This covers avatars on cards and on the task page, assignee and member pickers, comments, the member list, teammates and the dashboard's choice of teammate. The marker SHALL NOT rely on colour alone. Assignee pickers SHALL NOT offer deleted agents.

#### Scenario: Card
- **WHEN** a task assigned to agent Fish is on the board
- **THEN** its assignee avatar carries the agent marker

#### Scenario: Comment by a deleted agent
- **WHEN** a task shows a comment written by an agent that has since been deleted
- **THEN** the author is shown with the agent marker and marked as deleted

#### Scenario: Assignee picker
- **WHEN** a member opens the assignee picker of a task in a project with agent Fish and deleted agent Owl
- **THEN** Fish is offered with the agent marker, and Owl is not offered

## MODIFIED Requirements

### Requirement: Screens
The client SHALL provide screens for:
- a personal dashboard (own or a teammate's open tasks and upcoming deadlines);
- the project list and project creation;
- a project's board in kanban and list layouts;
- backlog;
- task details;
- sprints;
- milestones and a single milestone;
- members and invitations;
- agents;
- project settings (owner only);
- the project archive and an archived task;
- profile settings (name, language, contact links, avatar, password, API tokens, connected apps);
- announcements;
- feedback.

#### Scenario: Board screen
- **WHEN** a member opens a project's board
- **THEN** the project's columns are shown in order with their tasks, each card showing key, title, label, assignee avatar, deadline and importance

#### Scenario: Owner-only settings
- **WHEN** a non-owner member opens the project
- **THEN** no project settings entry is offered

#### Scenario: Agents entry
- **WHEN** any member opens a project
- **THEN** the project's sections include Agents
