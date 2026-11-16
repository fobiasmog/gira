## ADDED Requirements

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

## MODIFIED Requirements

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
