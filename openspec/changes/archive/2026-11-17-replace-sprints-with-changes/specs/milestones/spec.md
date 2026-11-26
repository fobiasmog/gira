## REMOVED Requirements

### Requirement: Create and list milestones
**Reason**: A change groups its own tasks and shows its own progress, so milestones duplicate it.
**Migration**: Group work as a change (spec `changes`). Its task counts replace milestone progress.

### Requirement: View a milestone
**Reason**: Removed with milestones.
**Migration**: List a change's tasks (spec `changes`, "Change task list").

### Requirement: Delete and recover
**Reason**: Removed with milestones.
**Migration**: None. Archive a change when its work is done.
