## ADDED Requirements

### Requirement: Requests on the change page
On the page of an open change (requirement "Change page"), the client SHALL show:
- when the change has no open request (spec `change-requests`), a button that asks for the step that fits its phase: "Start exploring" in Idea, "Write the proposal" in Exploring, "Implement" in Proposed, "Continue implementing" in Implementing, and "Archive and sync specs" in Done. Text in the comment field SHALL go with the request as its comment, and the field SHALL then be emptied;
- the change's request and agent in one line: "waiting for a free agent" for a waiting request with no agent; "queued for" the picked agent for a waiting request, saying when that agent is offline or which change it is on; who is working on it and since when for a taken request; that the agent's context is full and the change is blocked, for a blocked change (spec `change-requests`, "Full context"); and, with no open request, which agent is on the change or picked for it, if any;
- a "Cancel request" action while there is an open request. When that request is a reply request that is waiting, the button for the phase's step SHALL be shown as well;
- a "Release" action, naming the agent, while an agent is on the change, and an agent menu, offering "Any free agent" and the project's agents with their states, while no agent is on it;
- beside the comment field, while a comment would create a reply request, a note that posting asks the change's agent, or an agent, to reply.

While the change has an open request and the page is visible, the client SHALL reload the change and its thread at least every 15 seconds, so that the request's state, the agent's comments and the phase are shown without reloading the page. In the thread, each request asked for, taken, finished or cancelled, each release and each block SHALL appear as a history line naming who did it and which step or which agent. The page of an archived change SHALL offer no request or agent actions.

#### Scenario: Start exploring
- **WHEN** a member opens the page of `export-csv`, which is in Idea with no agent and no open request, and chooses "Start exploring"
- **THEN** the page says that the explore request is waiting for a free agent, offers "Cancel request", and no longer offers "Start exploring"

#### Scenario: Button for the phase
- **WHEN** a member opens the page of `export-csv`, which is in Proposed with no open request
- **THEN** the page offers "Implement"

#### Scenario: Comment with the step
- **WHEN** a member types "Start with the API." into the comment field of `export-csv` and chooses "Implement"
- **THEN** the comment is shown in the thread, the field is empty, and the page shows the implement request as open

#### Scenario: Queued for a busy agent
- **WHEN** a member chooses "Start exploring" on `add-tags`, which has agent Fish picked while Fish is on `export-csv`
- **THEN** the page says that the request is queued for Fish, who is on `export-csv`

#### Scenario: Taken request
- **WHEN** agent Fish took the implement request of `export-csv` at 14:05
- **THEN** the page says that Fish has been working on it since 14:05, and offers "Cancel request" and "Release Fish"

#### Scenario: Blocked
- **WHEN** Fish's context filled up while it was implementing `export-csv`, and a member opens the board and then the page of `export-csv`
- **THEN** the tab `export-csv` shows the waiting marker, and the page says that Fish's context is full and the change is blocked, and offers "Release Fish"

#### Scenario: Agent picks it up
- **WHEN** a member has the page of `export-csv` open with its explore request waiting, and Fish takes the request and later finishes it with questions
- **THEN** without reloading, the page shows that Fish is working on it, and later shows Fish's questions in the thread and no open request

#### Scenario: Cancel
- **WHEN** a member chooses "Cancel request" while the explore request of `export-csv` is waiting
- **THEN** the page shows no open request and offers "Start exploring" again

#### Scenario: Pick another agent
- **WHEN** a member chooses Heron in the agent menu of `add-tags`, which has Fish picked
- **THEN** the page says that Heron is picked for `add-tags`

#### Scenario: Release
- **WHEN** Fish is on `export-csv` and a member chooses "Release Fish"
- **THEN** the page shows no agent and offers the agent menu, and the thread shows a line saying that the member released Fish

#### Scenario: Reply note
- **WHEN** a member opens the page of `export-csv`, which is in Exploring with Fish on it and no open request
- **THEN** a note beside the comment field says that posting asks Fish to reply

#### Scenario: Request lines in the thread
- **WHEN** a member asked for an explore request on `export-csv` and Fish took it and finished it with questions
- **THEN** the thread shows the member asking for exploring, Fish taking it and finishing it, followed by Fish's questions

#### Scenario: Archived change
- **WHEN** a member opens the page of the archived change `fix-login`
- **THEN** no request button, "Cancel request", "Release" or agent menu is offered

## MODIFIED Requirements

### Requirement: New change dialog
The "New change" action, on the board and on the changes screen, SHALL open a dialog that asks for the change's name, optionally its idea in a Markdown text field, and its agent (spec `change-requests`, "Agent of a change"). The agent field SHALL offer "Any free agent", which is the default, and each of the project's agents with its state: free, on which change, or offline. As the member types the name, the dialog SHALL turn capital letters into lowercase and spaces into hyphens, and it SHALL show the allowed format. A validation error from the server SHALL be shown next to its field. After a change is created from the board, the board SHALL show that change.

#### Scenario: Typing a name
- **WHEN** a member types "Export CSV" into the name field
- **THEN** the field holds `export-csv`

#### Scenario: With an idea
- **WHEN** a member creates `export-csv` with the idea "People want a project's tasks as CSV."
- **THEN** the change's page shows that idea

#### Scenario: Pick an agent
- **WHEN** a member opens the dialog while Fish is on `export-csv`, Heron is free and Owl is offline, and creates `add-tags` with Fish
- **THEN** the agent field listed Fish as on `export-csv`, Heron as free and Owl as offline, and the page of `add-tags` says that Fish is picked

#### Scenario: Name taken
- **WHEN** a member submits the name `add-labels` while an open change has that name
- **THEN** the dialog stays open and shows the server's error next to the name field

#### Scenario: From the board
- **WHEN** a member creates the change `fix-login` from the board's "New change" action
- **THEN** the dialog closes and the board shows the tab `fix-login`

### Requirement: Agents screen
Each project SHALL have an Agents screen. It SHALL list the project's agents with their name, address, creator, number of live tokens, whether they are online or offline with their last check-in, and the change each one is on (spec `change-requests`, "Check-ins"), and its deleted agents in a collapsed group. From it, a member SHALL be able to:
- create an agent from a name, the first token's name, read-only or read-write access, its channels (API, MCP or both) and the current password;
- add an agent they can see from another of their projects;
- rename an agent;
- remove an agent from the project, except from its last project;
- delete an agent, after confirming;
- restore a deleted agent;
- list an agent's tokens with issuer, access, channels, last four characters, creation time and last use;
- issue a token with the same fields as at creation;
- revoke a token, after confirming.

A new token's value SHALL be shown once, with a copy control and a warning that it will not be shown again. When the token includes MCP, the screen SHALL also show a ready-to-copy MCP client configuration with the MCP endpoint and the value, a note that a client configured with it in a working copy acts as that agent there, and a link to the MCP guide. When it includes the API, the screen SHALL link to the API documentation.

#### Scenario: Create with MCP
- **WHEN** a member creates agent "Fish" with an MCP-only token and their correct password
- **THEN** the token's value is shown once with a copy control, a warning and an MCP client configuration containing it, and Fish appears in the list

#### Scenario: Agent states
- **WHEN** Fish checked in a minute ago and is on `export-csv`, and Owl last checked in two hours ago
- **THEN** the list shows Fish as online and on `export-csv`, and Owl as offline with its last check-in

#### Scenario: Wrong password
- **WHEN** a member submits the creation form with a wrong current password
- **THEN** the error is shown under the password field and the other fields keep their values

#### Scenario: Only project
- **WHEN** a member opens the actions of an agent that belongs to no other non-archived project
- **THEN** removing it from the project is not offered, and deleting it is

#### Scenario: Restore
- **WHEN** a member restores a deleted agent from the deleted group
- **THEN** the agent moves to the list of agents, with no tokens
