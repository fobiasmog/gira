# tasks Specification

## Purpose

Defines the task itself: how it is created, identified, edited, assigned, broken into subtasks, described in Markdown, archived and viewed after archiving.

## Requirements

### Requirement: Create a task
Members SHALL be able to create a task in a project with a title of 1 to 255 characters, optionally naming its column and its sprint. A task created without a column SHALL be placed on the project's first column. A named sprint SHALL be an open sprint of the same project. The creator SHALL be recorded. Each task SHALL receive a sequence number unique within its project, starting at 1 for the project's first task and increasing by one for each task created afterwards.

#### Scenario: First task in a project
- **WHEN** a member creates the first task of project "GOAL"
- **THEN** the task's sequence number is 1 and its key is "GOAL-1"

#### Scenario: Concurrent creation
- **WHEN** two members create tasks in the same project at the same moment
- **THEN** the two tasks receive different sequence numbers

#### Scenario: Create without a column
- **WHEN** a member creates a task without naming a column or a sprint in a project with columns "To Do", "Work", "Done"
- **THEN** the task is at the end of "To Do", belongs to no sprint, and is listed in the backlog

#### Scenario: Create in a planned sprint
- **WHEN** a member creates a task naming the planned sprint "S3"
- **THEN** the task belongs to "S3", is on the first column, and is listed with the tasks of "S3"

#### Scenario: Archived sprint
- **WHEN** a client creates a task naming an archived sprint or a sprint of another project
- **THEN** the request is rejected with a validation error and no task is created

### Requirement: Open a task by id or key
Members SHALL be able to open a task by its id or by its project sequence number. The response SHALL include the task's fields, column, creator, assignee, milestone, label, sprint, subtasks and comment count.

#### Scenario: Open by sequence number
- **WHEN** a member opens task number 12 of their project
- **THEN** the response is the task whose key is "<SHORT>-12"

### Requirement: Edit task fields
Members SHALL be able to change a task's title, description, deadline, importance flag, assignee and milestone. A referenced assignee SHALL be a current member of the task's project and SHALL NOT be a deleted agent (spec `agents`). A referenced milestone SHALL belong to the same project. Otherwise the change SHALL be rejected with a validation error and nothing SHALL be saved.

#### Scenario: Assign to a member
- **WHEN** a member assigns a task to another member of the project
- **THEN** the assignee is saved

#### Scenario: Assign to an agent
- **WHEN** a member assigns a task to agent Fish, a member of the project
- **THEN** the assignee is saved

#### Scenario: Assign to a deleted agent
- **WHEN** a client sets the assignee to the id of a deleted agent that belongs to the project
- **THEN** the update is rejected with a validation error and the task is unchanged

#### Scenario: Assign to an outsider
- **WHEN** a client sets the assignee to the id of a user who is not a member of the project
- **THEN** the update is rejected with a validation error, the task is unchanged, and no notification is sent

#### Scenario: Milestone from another project
- **WHEN** a client sets the milestone to one that belongs to another project
- **THEN** the update is rejected with a validation error and the task is unchanged

### Requirement: Markdown description
A task description SHALL be stored as Markdown text of at most 100,000 characters and returned exactly as stored. The server SHALL NOT convert descriptions to HTML.

#### Scenario: Round trip
- **WHEN** a member saves a description containing `# Plan` and `- [ ] write tests`
- **THEN** reading the task returns exactly the same text

#### Scenario: Raw HTML in description
- **WHEN** a member saves a description containing `<script>alert(1)</script>`
- **THEN** it is stored and returned as plain text, never executed or transformed by the server

### Requirement: Subtasks
Members SHALL be able to add subtasks to a root task. A subtask SHALL be a task of the same project with exactly one parent, placed on the project's first column when created. A subtask SHALL NOT have subtasks of its own. Subtasks SHALL NOT appear as separate cards on the board or in the backlog. A subtask SHALL count as complete when it is in the done column, and members SHALL be able to mark it complete or not complete.

#### Scenario: Add a subtask
- **WHEN** a member adds a subtask "Write tests" to task GOAL-3
- **THEN** the subtask is listed under GOAL-3 and is not shown as its own card on the board

#### Scenario: Nested subtask
- **WHEN** a client tries to add a subtask to a task that is itself a subtask
- **THEN** the request is rejected and nothing is created

#### Scenario: Mark subtask complete
- **WHEN** a member marks a subtask complete
- **THEN** the subtask is moved to the done column and counts as complete in its parent's subtask list

### Requirement: Archive and view archived tasks
Members SHALL be able to archive a task. Archived tasks SHALL disappear from the board, backlog, sprint, milestone, statistics and subtask lists, and SHALL appear in the project's archive list, newest first. Members SHALL be able to open an archived task read-only with its description, comments, subtasks, creator and assignee.

#### Scenario: Archive a task
- **WHEN** a member archives task GOAL-5
- **THEN** GOAL-5 is no longer on the board and appears at the top of the project's archive

#### Scenario: Edit an archived task
- **WHEN** a client tries to update an archived task
- **THEN** the request is rejected and the task is unchanged

### Requirement: Important flag and deadline
A task SHALL carry an optional deadline (date and time, stored in UTC) and an importance flag, both editable by members.

#### Scenario: Clear the deadline
- **WHEN** a member clears a task's deadline
- **THEN** the task has no deadline and no longer appears in upcoming-deadline lists

### Requirement: Tasks assigned to the requester
Members SHALL be able to list, in a project, the tasks assigned to themselves that are neither archived nor in the done column. The list SHALL include root tasks and subtasks alike, whatever their sprint. It SHALL be ordered by column, and by task number within a column. Each subtask SHALL identify its parent. With a token, the requester SHALL be the token's owner, so an agent lists its own tasks.

#### Scenario: An agent's work
- **WHEN** agent Fish lists its assigned tasks in GOAL with its token, and GOAL has these tasks:
  - GOAL-7 in "Work", assigned to Fish;
  - GOAL-9, a subtask of GOAL-7 in "To Do", assigned to Fish;
  - GOAL-3 in the done column, assigned to Fish;
  - GOAL-8, assigned to Owl
- **THEN** the list is GOAL-9 and then GOAL-7, and GOAL-9 identifies GOAL-7 as its parent

#### Scenario: Backlog and sprint
- **WHEN** Bob lists his assigned tasks in GOAL, and GOAL-4 is in the backlog while GOAL-5 is in the active sprint, both assigned to Bob
- **THEN** both GOAL-4 and GOAL-5 are listed

### Requirement: Name a task by id or key in every task request
Every request that names a task in its path SHALL accept the task's id or its key, as opening a task does: placing a task, putting it into a sprint, setting and removing its label, listing and adding its subtasks, completing and reopening a subtask, and listing and adding comments. A key SHALL identify the task by the number after its hyphen, within the request's project. A key or id that names no task of the project SHALL receive HTTP 404.

#### Scenario: Complete a subtask by key
- **WHEN** a member completes the subtask TEST-21, whose id is 23, by sending `TEST-21` as the task
- **THEN** TEST-21 is in the done column

#### Scenario: Comment by key
- **WHEN** a member adds a comment to `TEST-13`
- **THEN** the comment is listed on TEST-13

#### Scenario: Unknown key
- **WHEN** a member places `TEST-9999`, a key that names no task of TEST
- **THEN** the response is HTTP 404 and nothing changes
