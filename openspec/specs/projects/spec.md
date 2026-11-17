# projects Specification

## Purpose

Lets users create shared projects that group a board, tasks, changes and labels, and controls who can see and change them.

## Requirements

### Requirement: Create a project
The system SHALL let a signed-in user create a project with a title of 1 to 100 characters and a short name of 2 to 10 characters consisting of uppercase Latin letters and digits, starting with a letter. The creator SHALL become the project's owner and first member, and the project SHALL start with the default board columns.

#### Scenario: Valid project
- **WHEN** a user creates a project titled "Goalner" with short name "GOAL"
- **THEN** the project exists, the user is its owner and only member, and its board has the columns "To Do", "Work" and "Done"

#### Scenario: Invalid short name
- **WHEN** a user submits the short name "goal-1"
- **THEN** creation is rejected with a validation error on the short name

### Requirement: List and open projects
The system SHALL list only the non-archived projects the user is a member of. Every project-scoped request for a project the user is not a member of, or that does not exist, SHALL respond with HTTP 404 and SHALL NOT reveal whether the project exists.

#### Scenario: Member lists projects
- **WHEN** a user who belongs to projects A and B requests their project list
- **THEN** the response contains A and B and no other projects

#### Scenario: Non-member access
- **WHEN** a user requests any data of a project they do not belong to
- **THEN** the response is HTTP 404 with the same body as for a non-existent project

### Requirement: Board snapshot
The system SHALL return, for a project the user belongs to and for one of its open changes or for no change, in a single response: its columns; the root tasks of that board (spec `project-board`, "Board of a change"); members; labels; the change shown, or `null` for the board of other tasks; the project's open changes, newest first, each with its task counts (spec `changes`); and per-task counts of subtasks and comments.

#### Scenario: Snapshot of a change
- **WHEN** a member requests the board snapshot of TEST for the open change `add-labels`
- **THEN** the board tasks are exactly the root, non-archived tasks of `add-labels`, the change shown is `add-labels`, and the open changes of TEST are listed

#### Scenario: Snapshot without a change
- **WHEN** a member requests the board snapshot of TEST without naming a change
- **THEN** the response contains all root, non-archived tasks that belong to no change, the change shown is `null`, and the open changes of TEST are listed

#### Scenario: No open changes
- **WHEN** a member requests the board snapshot of a project without open changes
- **THEN** the list of open changes is empty and the tasks in no change are returned

### Requirement: Project settings are owner-only
Only the project owner SHALL be able to rename the project, change its short name, or archive it. Archiving SHALL hide the project and its content from all members while keeping the data recoverable by operators.

#### Scenario: Member tries to rename
- **WHEN** a non-owner member submits a new project title
- **THEN** the request is rejected with HTTP 403 and the title is unchanged

#### Scenario: Owner archives
- **WHEN** the owner archives the project
- **THEN** the project no longer appears in any member's project list and its project-scoped requests respond with HTTP 404

### Requirement: Leave a project
A non-owner member SHALL be able to leave a project, after which they lose access to it. The owner SHALL NOT be able to leave their own project.

#### Scenario: Member leaves
- **WHEN** a non-owner member leaves a project
- **THEN** the project disappears from their list and tasks assigned to them in that project become unassigned

#### Scenario: Owner tries to leave
- **WHEN** the owner requests to leave their own project
- **THEN** the request is rejected and the owner remains a member
