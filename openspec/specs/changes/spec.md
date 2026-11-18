# changes Specification

## Purpose

Lets a project hold many changes at once. Each change is one piece of work, planned with OpenSpec and built by agents or people, with its own tasks and its own board, and is archived when it is done. A change starts from an idea and moves through the phases Idea, Exploring, Proposed, Implementing and Done; it keeps a history of who moved it and who imported it, and shows when it is waiting for people to answer in its thread.

## Requirements

### Requirement: Changes in a project
A project SHALL hold changes. Each change SHALL have a name of 1 to 100 characters made of groups of lowercase Latin letters and digits joined by single hyphens. No two open changes of a project SHALL share a name, and a new change SHALL be allowed to take the name of an archived one. A change SHALL have no start or end date, and no change SHALL be marked as the active one: every open change is shown and worked on in the same way.

#### Scenario: Several open changes
- **WHEN** TEST holds the open changes `add-labels` and `export-csv`
- **THEN** both are listed as open, and neither is marked as active

#### Scenario: Name of an open change
- **WHEN** a member creates a change named `add-labels` while TEST already holds an open change `add-labels`
- **THEN** the response is HTTP 422 with a validation error on the name, and nothing is created

#### Scenario: Name of an archived change
- **WHEN** `add-labels` is archived and a member creates a change named `add-labels`
- **THEN** TEST holds a new open change `add-labels` with no tasks, and the archived one keeps its tasks

#### Scenario: Same name in two projects
- **WHEN** TEST holds the open change `add-agents` and a member creates a change named `add-agents` in GOAL
- **THEN** GOAL gets a change of its own, and TEST's change is unchanged

### Requirement: Create a change
Members of a non-archived project SHALL be able to create a change by giving its name and, optionally, its idea (requirement "Idea of a change"). The response SHALL be HTTP 201 with the change, which is open, in the phase Idea, and has no tasks. An import (spec `openspec-changes`) SHALL also create a change.

#### Scenario: Create
- **WHEN** a member creates a change named `export-csv` in TEST
- **THEN** the response is HTTP 201, and TEST holds the open change `export-csv` in the phase Idea, with no tasks

#### Scenario: Invalid name
- **WHEN** a member creates a change named `Export CSV`
- **THEN** the response is HTTP 422 with a validation error on the name, and nothing is created

#### Scenario: Agent through MCP
- **WHEN** a client holding agent Fish's read-write MCP token calls the create tool for TEST with the name `fix-login`
- **THEN** TEST holds the open change `fix-login`

#### Scenario: Archived project
- **WHEN** a member creates a change in an archived project
- **THEN** the response is HTTP 404 and nothing is created

### Requirement: Tasks in a change
Members SHALL be able to put a root task of the project into one of the project's open changes, move it to another open change, or take it out of its change, which leaves it in no change. A task SHALL belong to at most one change and SHALL keep its column when its change changes. A subtask SHALL belong to its parent's change and SHALL follow its parent when the parent moves. A card whose mark is in its change's tasks text (spec `openspec-changes`) SHALL stay in its change: moving it to another change or out of its change SHALL be refused with a validation error.

#### Scenario: Change of another project
- **WHEN** a client puts a task into a change id that belongs to another project
- **THEN** the request is rejected and the task's change is unchanged

#### Scenario: Archived change
- **WHEN** a client puts a task into an archived change
- **THEN** the request is rejected and the task's change is unchanged

#### Scenario: Move to another change
- **WHEN** a member moves task TEST-9, which is in "Work" in `fix-login` and has two subtasks, to `export-csv`
- **THEN** TEST-9 and its two subtasks belong to `export-csv`, TEST-9 is still in "Work", and it is no longer listed with the tasks of `fix-login`

#### Scenario: Take a task out of its change
- **WHEN** a member takes task TEST-9, which is in "Work" in `fix-login`, out of its change
- **THEN** TEST-9 belongs to no change, is still in "Work", and is shown on the board of tasks in no change (spec `project-board`)

#### Scenario: Card of tasks.md
- **WHEN** a member moves TEST-20, a card whose mark is in the tasks text of `add-labels`, to `export-csv`
- **THEN** the response is HTTP 422 with a validation error, and TEST-20 stays in `add-labels`

### Requirement: Change task list
Members SHALL be able to list the root, non-archived tasks of one change of their project, open or archived, done ones included, ordered by column order and then by position within the column. Each listed task SHALL include its column.

#### Scenario: Tasks of a change
- **WHEN** a member lists the tasks of `export-csv`, which holds one task in "Done" and two in "To Do"
- **THEN** the two "To Do" tasks are listed first in their column order, followed by the "Done" task

#### Scenario: Change of another project
- **WHEN** a member requests, within their project, the task list of a change id that belongs to another project
- **THEN** the response is HTTP 404 and no tasks are returned

### Requirement: Change lists and statistics
Members SHALL be able to list the project's open changes, newest first, and its archived changes, most recently archived first. Each listed change SHALL include its phase (requirement "Phase of a change"), whether it is waiting for people (requirement "Waiting for people"), its number of root, non-archived tasks per column and their total, and, for an archived change, when it was archived.

#### Scenario: Change statistics
- **WHEN** a member lists the open changes of a project where `add-labels` has 2 cards in "To Do" and 1 in "Done", and its cards have 9 subtasks
- **THEN** `add-labels` is reported with counts To Do 2, Done 1 and total 3

#### Scenario: Archived changes
- **WHEN** `add-labels` was archived yesterday and `fix-login` today, and a member lists the archived changes
- **THEN** the list is `fix-login` followed by `add-labels`, each with its archive time, and neither is in the list of open changes

#### Scenario: Phase and waiting in the list
- **WHEN** a member lists the open changes while `export-csv` is in Exploring and the newest comment of its thread is agent Fish's
- **THEN** `export-csv` is listed in the phase Exploring and as waiting for people

### Requirement: Open a change
Members SHALL be able to open a change of their project by its id or by its name. A name SHALL find the project's open change of that name, and a value made only of digits SHALL be read as an id. The response SHALL contain the change's name, when it was archived or `null`, its idea, its phase, whether it is waiting for people, its task counts, its cards that are not archived, each with its subtask counts, its history (requirement "Change history"), and the paths of its files (spec `openspec-changes`, "Files of a change"). An id or name that finds no change of the project SHALL receive HTTP 404.

#### Scenario: Open by name
- **WHEN** a member opens `add-labels` in TEST
- **THEN** the response contains the change `add-labels` and its cards

#### Scenario: Idea, phase and history
- **WHEN** a member opens `export-csv`, which was created with an idea and moved to Exploring by agent Fish
- **THEN** the response contains its idea, the phase Exploring, and a history holding Fish's move to Exploring

#### Scenario: Unknown change
- **WHEN** a member opens the change `no-such-change`
- **THEN** the response is HTTP 404

#### Scenario: Archived change by name
- **WHEN** the only change named `add-labels` in TEST is archived and a member opens `add-labels`
- **THEN** the response is HTTP 404, and opening the change by its id returns it

### Requirement: Archive a change
Members SHALL be able to archive an open change, whatever the state of its tasks. An archived change SHALL keep its tasks, SHALL appear only in the list of archived changes, and SHALL have no board. No task SHALL be put into an archived change. Archiving a change that is already archived SHALL leave it as it is.

#### Scenario: Archive with unfinished cards
- **WHEN** a member archives `add-labels`, which has 1 card in the done column and 3 elsewhere
- **THEN** `add-labels` is archived and listed among the archived changes, its four cards still belong to it, and none of them is shown on any board

#### Scenario: Archive twice
- **WHEN** a client archives `add-labels`, which was archived yesterday
- **THEN** the request succeeds and its archive time is still yesterday's

### Requirement: Tasks name their change
Tasks in lists and in task details SHALL include the change they belong to, with its id and name, or `null` for a task in no change. They SHALL also say whether the task's mark is in its change's tasks text (spec `openspec-changes`).

#### Scenario: Card of a change
- **WHEN** a member opens TEST-20, a card created by importing `add-labels`
- **THEN** the response names the change `add-labels` and says that TEST-20 is marked in its tasks text

#### Scenario: Task added by hand to a change
- **WHEN** a member opens TEST-30, which was created on the board of `add-labels`
- **THEN** the response names the change `add-labels` and says that TEST-30 is not marked in its tasks text

#### Scenario: Task in no change
- **WHEN** a member opens a task that belongs to no change
- **THEN** its change is `null`

### Requirement: Idea of a change
A change SHALL have an idea: Markdown text of at most 100,000 characters, stored and returned exactly as written, or `null`. Members SHALL be able to give the idea when they create a change, and to set, change or clear it while the change is in the phase Idea (requirement "Phase of a change"). Changing the idea of a change in any other phase, or of an archived change, SHALL be refused with a validation error and SHALL change nothing. A change created by an import (spec `openspec-changes`) SHALL have no idea.

#### Scenario: Create with an idea
- **WHEN** a member creates the change `export-csv` with the idea "People want a project's tasks as CSV for weekly reports."
- **THEN** TEST holds the open change `export-csv`, in the phase Idea, with that idea

#### Scenario: Edit before exploring
- **WHEN** a member changes the idea of `export-csv`, which is in the phase Idea
- **THEN** opening `export-csv` returns the new idea

#### Scenario: Fixed once exploring starts
- **WHEN** agent Fish moved `export-csv` to Exploring, and a member then changes its idea
- **THEN** the response is HTTP 422 with a validation error on the idea, and the idea is unchanged

#### Scenario: Idea too long
- **WHEN** a member creates a change with an idea of 100,001 characters
- **THEN** the response is HTTP 422 with a validation error on the idea, and nothing is created

### Requirement: Phase of a change
A change SHALL be in one of the phases Idea, Exploring, Proposed, Implementing and Done, in that order. A change created by a member SHALL start in Idea, and a change created by an import SHALL start in Proposed (spec `openspec-changes`). Members SHALL be able to move an open change to Idea, Exploring, Proposed or Implementing, from any phase. A change in Implementing SHALL be reported in the phase Done while it has at least one card and all of its cards are in the done column, and SHALL be reported in Implementing again as soon as one of its cards is not. Here a card is a root task of the change that is not archived. Moving a change to Done, or moving an archived change to any phase, SHALL be refused with a validation error and SHALL change nothing. An archived change SHALL keep the phase it had.

#### Scenario: New change
- **WHEN** a member creates the change `export-csv`
- **THEN** `export-csv` is in the phase Idea

#### Scenario: Agent moves the phase
- **WHEN** a client holding agent Fish's read-write MCP token moves `export-csv` to Exploring
- **THEN** `export-csv` is in the phase Exploring

#### Scenario: Back to an earlier phase
- **WHEN** a member moves `export-csv`, which is in Proposed, to Exploring
- **THEN** `export-csv` is in the phase Exploring

#### Scenario: Done
- **WHEN** `add-labels` is in Implementing and the last of its 4 cards is moved to the done column
- **THEN** `add-labels` is reported in the phase Done

#### Scenario: Out of Done
- **WHEN** a card of `add-labels`, which is reported in Done, is moved out of the done column
- **THEN** `add-labels` is reported in the phase Implementing

#### Scenario: Implementing without cards
- **WHEN** a member moves `fix-login`, which has no cards, to Implementing
- **THEN** `fix-login` is reported in the phase Implementing

#### Scenario: Done cannot be chosen
- **WHEN** a member moves `export-csv` to Done
- **THEN** the response is HTTP 422 with a validation error on the phase, and the phase is unchanged

#### Scenario: Archived change
- **WHEN** a member moves the archived change `fix-login` to Exploring
- **THEN** the response is HTTP 422 with a validation error, and its phase is unchanged

### Requirement: Change history
Goalner SHALL record for each change every move to another phase (requirement "Phase of a change") and every import (spec `openspec-changes`), each with who made it and when, and for an import the paths of the files it brought, `tasks.md` included. Being reported in Done or leaving Done SHALL NOT be recorded, and moving a change to the phase it is in SHALL record nothing. Opening a change SHALL return its history, oldest first.

#### Scenario: Phase moves
- **WHEN** agent Fish moves `export-csv` to Exploring and later a member moves it to Implementing
- **THEN** the history of `export-csv` lists Fish's move to Exploring followed by the member's move to Implementing, each with its time

#### Scenario: Import
- **WHEN** Fish imports `export-csv`, which is in Exploring, with a proposal, the spec `export` and a tasks text
- **THEN** the history lists the import by Fish with the files `proposal.md`, `specs/export/spec.md` and `tasks.md`, and Fish's move to Proposed

#### Scenario: Same phase
- **WHEN** a member moves `export-csv`, which is in Proposed, to Proposed
- **THEN** nothing is added to its history

### Requirement: Waiting for people
An open change SHALL be waiting for people when the newest comment of its thread (spec `comments`, "Comment on a change") was written by an agent (spec `agents`). A change without comments, or whose newest comment was written by a person, SHALL NOT be waiting, and an archived change SHALL never be waiting.

#### Scenario: Agent asked
- **WHEN** Fish's comment "Should archived tasks go into the file?" is the newest comment of the thread of `export-csv`
- **THEN** `export-csv` is waiting for people

#### Scenario: Answered
- **WHEN** a member then replies "No." on `export-csv`
- **THEN** `export-csv` is not waiting for people

#### Scenario: No thread
- **WHEN** the change `fix-login` has no comments
- **THEN** `fix-login` is not waiting for people
