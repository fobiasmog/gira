# Proposal

## Why

The backlog lists tasks that have no column, while the board lists only the active sprint's tasks on a column. A task that is on a column but in no sprint, while a sprint is active, appears on neither screen and can only be reached by its URL (TEST-1 in the dev database: created on the board before the first sprint was started). The same happens to a task created in the backlog and then sent "To board" during a sprint, and to a board task taken out of its sprint on the task page. Planned sprints have the same blind spot: their tasks are invisible until the sprint starts, because the sprints screen shows only counts.

## What Changes

- **BREAKING** Every task always has a column. A task created without one gets the project's first column (lowest position). Existing tasks without a column are moved to their project's first column, and the column becomes mandatory in the database. The placement API no longer accepts "no column".
- **BREAKING** The backlog is defined by sprint, not by column: it is the root, non-archived tasks that belong to no sprint and are not done, whatever other column they are in. Done tasks in no sprint get their own listing, so they stay reachable while a sprint is active.
- The board is unchanged in rule but now covers everything: with an active sprint it shows that sprint's tasks; without one it shows the tasks in no sprint.
- **BREAKING** "Move to backlog" takes a task out of its sprint and keeps its column. Without an active sprint the board does not offer it.
- "To board" on a backlog task (offered only while a sprint is active) puts the task into the active sprint at the chosen column, in one request.
- Deleting a column moves its tasks to the project's first remaining column instead of the backlog. When only the done column remains, they become done.
- Task creation accepts a sprint, so a task can be added directly to the backlog or to any open sprint.
- New listing of one sprint's tasks, done ones included, each saying which sprint holds its copy if it was carried over.
- Backlog screen: a list of the open tasks in no sprint, each showing its column, with an add field and a "Move" menu (any open sprint, or the board while a sprint is active). A collapsed "Done (n)" group below the list holds the done tasks in no sprint.
- Sprints screen redesigned as a planning page: each open sprint is a collapsible section listing its tasks with an add field and a "Move" menu per task (another sprint, the backlog), with the sprint's dates, counts and actions in the section header. Done tasks are marked as done and carried-over tasks show "Carried to <sprint>". Archived sprints stay in a collapsed list.
- The task page's column control no longer offers "Backlog".

Not included: a sprint picker on the board (without an active sprint the board always shows the tasks in no sprint), drag and drop between backlog and sprint sections, and manual reordering inside a backlog or sprint section.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `project-board`: the backlog is redefined by sprint and excludes done tasks, which get their own listing; deleting a column moves its tasks to the first remaining column; a placement always names a column; the board's rule covers projects without an active sprint; the backlog requirement covers moving tasks between the board and the backlog.
- `tasks`: a task created without a column goes to the first column, and creation accepts a sprint.
- `sprints`: tasks can be taken out of a sprint, and a sprint's tasks can be listed.
- `web-client`: adds the backlog screen, the sprint planning screen, and offers "Move to backlog" on the board only during a sprint.

## Impact

- Database: a migration that moves tasks without a column to their project's first column (appended in their current order) and sets `tasks.status_id` to `NOT NULL`.
- Backend: `Task` (default column, `in_backlog` scope by sprint), `Board#place` (column required, optional sprint change), `Board#delete_column`, `Api::Projects::TasksController` (`view=backlog` by sprint, new `view=backlog_done`, `sprint_id` on create), a new nested sprint tasks endpoint, `Api::Projects::Tasks::PlacementsController`, `Sprint#task_counts` (no "backlog" bucket), `Statistics#overview` (no backlog group). The `statistics` spec does not change.
- Frontend: `api/tasks.ts`, `api/types.ts` (`status_id` no longer nullable), stores `backlog`, `board`, `sprints`, pages `BacklogPage`, `SprintsPage`, `TaskPage`, `components/board/BoardList.vue` ("Move to backlog"), and `i18n/en.ts` / `i18n/ru.ts`.
- Tests: model and request tests for the backlog definition, placement, column deletion and creation; system tests for the backlog and sprints screens. Tests and fixtures that create tasks without a column need updating.
