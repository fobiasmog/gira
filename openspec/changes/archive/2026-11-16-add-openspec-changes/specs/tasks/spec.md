## ADDED Requirements

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
