## ADDED Requirements

### Requirement: Files of a change
An import SHALL store the OpenSpec files it was sent as the change's files, each with its text exactly as sent: `proposal.md` for `proposal`, `design.md` for `design`, and `specs/<capability path>/spec.md` for each delta spec. The files of a change SHALL be those sent by its last import: a file that the last import did not send SHALL no longer belong to the change. Opening a change (spec `changes`) SHALL list the paths of its files, `proposal.md` first, then `design.md`, then the spec files ordered by path. Members SHALL be able to read one file of a change, open or archived, by its path. A path that names no file of the change SHALL receive HTTP 404. `tasks.md` SHALL NOT be a stored file: its text is the change's marked text (requirement "Read a change").

#### Scenario: Files stored
- **WHEN** agent Fish imports `export-csv` with a proposal, a design, the spec `export` and a tasks text
- **THEN** opening `export-csv` lists the files `proposal.md`, `design.md` and `specs/export/spec.md`, and reading `proposal.md` returns the proposal exactly as sent

#### Scenario: File no longer sent
- **WHEN** `export-csv` is imported again with a proposal, the spec `export` and its marked tasks text, but no design
- **THEN** opening `export-csv` lists `proposal.md` and `specs/export/spec.md`, and reading `design.md` receives HTTP 404

#### Scenario: Unknown path
- **WHEN** a member reads the file `notes.md` of `export-csv`
- **THEN** the response is HTTP 404

#### Scenario: Archived change
- **WHEN** a read-only token for TEST reads `proposal.md` of the archived change `add-labels` by the change's id
- **THEN** the proposal is returned

## MODIFIED Requirements

### Requirement: Import a change
A member of a non-archived project SHALL be able to import an OpenSpec change by sending its name and, under `artifacts`, the text of its `tasks.md` as `tasks` and, optionally, the text of its `proposal.md` as `proposal`, of its `design.md` as `design`, and of its delta specs as `specs`: an object whose keys are the capability paths of the delta specs (the folders under the change's `specs/`, such as `export` or `identity/user-auth`) and whose values are the texts of their `spec.md`. The import SHALL work on the project's open change of that name (spec `changes`). When the project has no open change of that name, the import SHALL create it and SHALL respond with HTTP 201; otherwise it SHALL respond with HTTP 200. The first import into a change SHALL create its cards and their subtasks, and a later import SHALL update them (requirement "Import again"). The import SHALL store the files it was sent (requirement "Files of a change"). An import into a change in the phase Idea or Exploring SHALL move it to Proposed, a change created by an import SHALL start in Proposed, and an import SHALL leave a change in any other phase in its phase (spec `changes`, "Phase of a change"). An import SHALL succeed or fail as a whole: when any part of it is refused, nothing SHALL change. The response SHALL contain the change, its marked text (requirement "Goalner keys in the tasks text"), its cards and the paths of its files. Any other artifact SHALL be refused with a validation error. A capability path SHALL be one or more groups of lowercase Latin letters and digits joined by single hyphens, separated by single slashes, and any other key under `specs` SHALL be refused with a validation error naming it. The name SHALL follow the rules for change names (spec `changes`), and an invalid name SHALL be refused with a validation error. The importer SHALL be recorded as the creator of the tasks the import creates, and as the change's last importer, with the time of the import. An import SHALL NOT assign tasks to anyone and SHALL NOT send any notification.

#### Scenario: First import
- **WHEN** a member imports `add-labels` into TEST, which has no open change of that name, with a `tasks` text holding two sections of three items each
- **THEN** the response is HTTP 201, TEST holds the open change `add-labels` in the phase Proposed, and it has two new cards with three subtasks each, created by the member and assigned to nobody

#### Scenario: Change created by hand
- **WHEN** a member created the change `export-csv` on the changes screen, added the task TEST-31 to it by hand, agent Fish moved it to Exploring, and Fish then imports `export-csv` for the first time
- **THEN** the response is HTTP 200, the cards and subtasks are created in `export-csv`, `export-csv` is in the phase Proposed, and TEST-31 is left as it is

#### Scenario: Import again
- **WHEN** a member imports `add-labels` a second time with the marked text returned by the first import
- **THEN** the response is HTTP 200 and no task is created

#### Scenario: Import during implementation
- **WHEN** a member imports `add-labels`, which is in Implementing, with its marked text and one more item
- **THEN** `add-labels` stays in Implementing and the item becomes a new subtask

#### Scenario: All the files
- **WHEN** agent Fish imports `export-csv` with `proposal`, `design`, `tasks` and `specs` holding `export` and `identity/user-auth`
- **THEN** the response is HTTP 200 or 201 and lists the files `proposal.md`, `design.md`, `specs/export/spec.md` and `specs/identity/user-auth/spec.md`

#### Scenario: Invalid name
- **WHEN** a member imports a change named `Add Labels`
- **THEN** the response is HTTP 422 with a validation error on the name, and nothing is created

#### Scenario: All or nothing
- **WHEN** a member imports a text in which one item carries the mark of a task of another change
- **THEN** the response is HTTP 422, and no change, task or file is created or changed

#### Scenario: Import after archiving
- **WHEN** `add-labels` was archived and a member imports `add-labels` with the marked text it last returned
- **THEN** the response is HTTP 422 with a validation error naming the first marked line, because the marks name tasks of the archived change, and no change is created

#### Scenario: Other artifacts
- **WHEN** a member imports `add-labels` with artifacts `tasks` and `notes`
- **THEN** the response is HTTP 422 with a validation error on `notes`, and nothing changes

#### Scenario: Invalid capability path
- **WHEN** a member imports `add-labels` with `specs` holding the key `../secrets`
- **THEN** the response is HTTP 422 with a validation error naming `../secrets`, and nothing changes

#### Scenario: Archived project
- **WHEN** a member imports a change into an archived project
- **THEN** the response is HTTP 404 and nothing is created

#### Scenario: Agent through MCP
- **WHEN** a client holding agent Fish's read-write MCP token calls the import tool for TEST
- **THEN** the cards and subtasks are created in TEST with Fish as their creator

### Requirement: Limits of a change
The `tasks` text SHALL be at most 100,000 characters long, and SHALL hold at most 50 sections and 500 items. The proposal, the design and each delta spec SHALL each be at most 100,000 characters long, and an import SHALL carry at most 50 delta specs. An import that would exceed a limit SHALL be refused with a validation error and SHALL change nothing.

#### Scenario: Too many items
- **WHEN** a member imports a text with 501 items
- **THEN** the response is HTTP 422 and nothing is created

#### Scenario: Proposal too long
- **WHEN** a member imports a change with a proposal of 100,001 characters
- **THEN** the response is HTTP 422 with a validation error on the proposal, and nothing changes

#### Scenario: Too many specs
- **WHEN** a member imports a change with 51 delta specs
- **THEN** the response is HTTP 422 with a validation error on the specs, and nothing changes
