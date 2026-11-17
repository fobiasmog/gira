## ADDED Requirements

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

## REMOVED Requirements

### Requirement: Project board snapshot
**Reason**: The snapshot is no longer taken for the active sprint. Replaced by "Board snapshot", taken for one change or for no change.
**Migration**: See requirement "Board snapshot". Clients name the change to show; the snapshot names `change` instead of `active_sprint`, and lists the open changes.
