## MODIFIED Requirements

### Requirement: Change history
Goalner SHALL record for each change every move to another phase (requirement "Phase of a change"), every import (spec `openspec-changes`), and every request asked for, taken, finished and cancelled (spec `change-requests`), each with who made it and when; for an import, the paths of the files it brought, `tasks.md` included; and for a request, its kind and, once finished, whether it was done or failed. Being reported in Done or leaving Done SHALL NOT be recorded, and moving a change to the phase it is in SHALL record nothing. Opening a change SHALL return its history, oldest first.

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

### Requirement: Waiting for people
An open change SHALL be waiting for people when it has no open request (spec `change-requests`) and the newest comment of its thread (spec `comments`, "Comment on a change") was written by an agent (spec `agents`). A change without comments, a change whose newest comment was written by a person, a change with an open request, and an archived change SHALL NOT be waiting.

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
