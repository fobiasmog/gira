## REMOVED Requirements

### Requirement: Create a sprint
**Reason**: Sprints are replaced by changes, which have no dates and are never "active".
**Migration**: Create a change instead (spec `changes`, "Create a change").

### Requirement: Single active sprint
**Reason**: Every open change is shown and worked on in the same way; nothing is active.
**Migration**: Pick a change's tab on the board (spec `web-client`, "Board change tabs").

### Requirement: Carry over unfinished tasks
**Reason**: Changes are not time-boxed, so unfinished work is never copied forward.
**Migration**: None. Unfinished tasks stay with their change, also after it is archived.

### Requirement: Add tasks to a sprint
**Reason**: Replaced by putting tasks into changes.
**Migration**: See spec `changes`, "Tasks in a change". The task operation that set a task's sprint now sets its change.

### Requirement: Sprint task list
**Reason**: Replaced by the change task list.
**Migration**: See spec `changes`, "Change task list". Tasks no longer name a sprint holding a carried-over copy.

### Requirement: Sprint lists and statistics
**Reason**: Replaced by the change lists. The list of sprints available for planning has no counterpart, because every open change is available.
**Migration**: See spec `changes`, "Change lists and statistics".

### Requirement: Archive a sprint
**Reason**: Replaced by archiving a change, without carry-over.
**Migration**: See spec `changes`, "Archive a change".
