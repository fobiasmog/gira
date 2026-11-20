## MODIFIED Requirements

### Requirement: Create a change
Members of a non-archived project SHALL be able to create a change by giving its name and, optionally, its idea (requirement "Idea of a change") and its agent (spec `change-requests`, "Agent of a change"). The response SHALL be HTTP 201 with the change, which is open, in the phase Idea, and has no tasks. An import (spec `openspec-changes`) SHALL also create a change.

#### Scenario: Create
- **WHEN** a member creates a change named `export-csv` in TEST
- **THEN** the response is HTTP 201, and TEST holds the open change `export-csv` in the phase Idea, with no tasks and no agent

#### Scenario: With an agent
- **WHEN** a member creates a change named `add-tags` in TEST with agent Fish picked
- **THEN** the response is HTTP 201, and `add-tags` is in the phase Idea with Fish picked

#### Scenario: Invalid name
- **WHEN** a member creates a change named `Export CSV`
- **THEN** the response is HTTP 422 with a validation error on the name, and nothing is created

#### Scenario: Agent through MCP
- **WHEN** a client holding agent Fish's read-write MCP token calls the create tool for TEST with the name `fix-login`
- **THEN** TEST holds the open change `fix-login`

#### Scenario: Archived project
- **WHEN** a member creates a change in an archived project
- **THEN** the response is HTTP 404 and nothing is created

### Requirement: Archive a change
Members SHALL be able to archive an open change, whatever the state of its tasks. Archiving SHALL cancel the change's open request (spec `change-requests`), recorded as cancelled by whoever archived it, and the change's agent SHALL then be free. An archived change SHALL keep its tasks, SHALL appear only in the list of archived changes, and SHALL have no board. No task SHALL be put into an archived change. Archiving a change that is already archived SHALL leave it as it is.

#### Scenario: Archive with unfinished cards
- **WHEN** a member archives `add-labels`, which has 1 card in the done column and 3 elsewhere
- **THEN** `add-labels` is archived and listed among the archived changes, its four cards still belong to it, and none of them is shown on any board

#### Scenario: Archive with an open request
- **WHEN** agent Fish is on `export-csv` and has taken its implement request, and a member archives `export-csv`
- **THEN** `export-csv` is archived, the implement request is cancelled by the member, and Fish is free

#### Scenario: Archive twice
- **WHEN** a client archives `add-labels`, which was archived yesterday
- **THEN** the request succeeds and its archive time is still yesterday's

### Requirement: Change history
Goalner SHALL record for each change every move to another phase (requirement "Phase of a change"), every import (spec `openspec-changes`), every request asked for, taken, finished and cancelled, every release of its agent, and every block for a full context (spec `change-requests`), each with who made it and when; for an import, the paths of the files it brought, `tasks.md` included; for a request, its kind and, once finished, whether it was done or failed; and for a release, the agent released. Being reported in Done or leaving Done SHALL NOT be recorded, and moving a change to the phase it is in SHALL record nothing. Opening a change SHALL return its history, oldest first.

#### Scenario: Phase moves
- **WHEN** agent Fish moves `export-csv` to Exploring and later a member moves it to Implementing
- **THEN** the history of `export-csv` lists Fish's move to Exploring followed by the member's move to Implementing, each with its time

#### Scenario: Import
- **WHEN** Fish imports `export-csv`, which is in Exploring, with a proposal, the spec `export` and a tasks text
- **THEN** the history lists the import by Fish with the files `proposal.md`, `specs/export/spec.md` and `tasks.md`, and Fish's move to Proposed

#### Scenario: Same phase
- **WHEN** a member moves `export-csv`, which is in Proposed, to Proposed
- **THEN** nothing is added to its history

#### Scenario: A request from start to end
- **WHEN** a member asks for an explore request on `export-csv`, Fish takes it and later finishes it as done
- **THEN** the history lists, in order, the member asking for exploring, Fish taking it, Fish's move to Exploring, and Fish finishing it as done

#### Scenario: Release
- **WHEN** Fish is on `export-csv`, and a member releases Fish
- **THEN** the history lists the member releasing Fish

#### Scenario: Block
- **WHEN** Fish is on `export-csv` and reports that its context is full
- **THEN** the history lists that Fish's context is full and the change is blocked

### Requirement: Waiting for people
An open change SHALL be waiting for people when it is blocked (spec `change-requests`, "Full context"), or when it has no open request (spec `change-requests`) and the newest comment of its thread (spec `comments`, "Comment on a change") was written by an agent (spec `agents`). Otherwise a change without comments, a change whose newest comment was written by a person, a change with an open request, and an archived change SHALL NOT be waiting.

#### Scenario: Agent asked
- **WHEN** Fish's comment "Should archived tasks go into the file?" is the newest comment of the thread of `export-csv`, and `export-csv` has no open request
- **THEN** `export-csv` is waiting for people

#### Scenario: Answered
- **WHEN** a member then replies "No." on `export-csv`
- **THEN** `export-csv` is not waiting for people

#### Scenario: No thread
- **WHEN** the change `fix-login` has no comments
- **THEN** `fix-login` is not waiting for people

#### Scenario: Request open
- **WHEN** Fish's comment is the newest on `export-csv`, and a member asked for an implement request without a comment
- **THEN** `export-csv` is not waiting for people while the request is open

#### Scenario: Blocked
- **WHEN** Fish has taken the implement request of `export-csv`, and `export-csv` is blocked because Fish's context is full
- **THEN** `export-csv` is waiting for people, although its request is open
