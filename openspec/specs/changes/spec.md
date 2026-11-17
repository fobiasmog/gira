# changes Specification

## Purpose

Lets a project hold many changes at once. Each change is one piece of work, planned with OpenSpec and built by agents or people, with its own tasks and its own board, and is archived when it is done.

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
Members of a non-archived project SHALL be able to create a change by giving its name. The response SHALL be HTTP 201 with the change, which is open and has no tasks. An import (spec `openspec-changes`) SHALL also create a change.

#### Scenario: Create
- **WHEN** a member creates a change named `export-csv` in TEST
- **THEN** the response is HTTP 201, and TEST holds the open change `export-csv` with no tasks

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
Members SHALL be able to list the project's open changes, newest first, and its archived changes, most recently archived first. Each listed change SHALL include its number of root, non-archived tasks per column and their total, and, for an archived change, when it was archived.

#### Scenario: Change statistics
- **WHEN** a member lists the open changes of a project where `add-labels` has 2 cards in "To Do" and 1 in "Done", and its cards have 9 subtasks
- **THEN** `add-labels` is reported with counts To Do 2, Done 1 and total 3

#### Scenario: Archived changes
- **WHEN** `add-labels` was archived yesterday and `fix-login` today, and a member lists the archived changes
- **THEN** the list is `fix-login` followed by `add-labels`, each with its archive time, and neither is in the list of open changes

### Requirement: Open a change
Members SHALL be able to open a change of their project by its id or by its name. A name SHALL find the project's open change of that name, and a value made only of digits SHALL be read as an id. The response SHALL contain the change's name, when it was archived or `null`, its task counts, and its cards that are not archived, each with its subtask counts. An id or name that finds no change of the project SHALL receive HTTP 404.

#### Scenario: Open by name
- **WHEN** a member opens `add-labels` in TEST
- **THEN** the response contains the change `add-labels` and its cards

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
