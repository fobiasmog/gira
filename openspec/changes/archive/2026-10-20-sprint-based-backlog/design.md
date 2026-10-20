# Design

## Context

See proposal.md for the problem. Today two independent attributes decide where a root task shows up:

- `status_id` (column): `NULL` means "backlog". `Task.in_backlog` and `view=backlog` filter on it alone.
- `sprint_id`: the board (`BoardsController#show`, `TasksController#board_tasks`) shows `status_id IS NOT NULL AND sprint_id = <active sprint or NULL>`.

The two filters are not complements, so tasks on a column outside the active sprint (and tasks on a column in a planned sprint) fall between them. `Board#place` changes only the column, so "To board" from the backlog during a sprint creates such a task. Positions are kept by `acts_as_list` scoped to `project_id, status_id, sprint_id, parent_id`. Subtasks already get `Project#first_status` on creation.

## Goals / Non-Goals

**Goals:**
- A single attribute (the sprint) decides which screen shows a task, and every task always has a column.
- Every root, non-archived task is listed somewhere:
  - in the active sprint: the board;
  - in no sprint: the board when no sprint is active, otherwise the backlog (open tasks) or the backlog's done group;
  - in any other sprint: that sprint's section on the sprints screen.
- "To board" is a single atomic request.

**Non-Goals:**
- No new tables or columns; carry-over and sprint activation are unchanged.
- No remembering which sections a viewer collapsed.
- No changes to how positions are scoped.

## Decisions

### 1. The column is mandatory, defaulting to the first column

A task created without a column gets `project.first_status` (a `before_validation on: :create` default in `Task`), and the column gets a presence validation and a `NOT NULL` constraint. Subtask creation then needs no special case.

- *Alternative: keep `NULL` and treat it as "first column" in queries.* Rejected: two spellings of one state, and every query and the client would need to know about both.
- *Alternative: give tasks a column only when a sprint is activated.* Rejected: it only covers one of the ways tasks fall through (see proposal.md).

### 2. Backlog and board use the same predicate on `sprint_id`

`Task.in_backlog` becomes `where(sprint_id: nil)`; the `on_board` scope goes away.

- **Board:** `kept.roots.where(sprint_id: project.active_sprint&.id)`.
- **Backlog:** `kept.roots.in_backlog.not_done`.
- **Ordering:** both lists, and the sprint task list (decision 8), are ordered by column position, then task position (`joins(:status).order("statuses.position", :position)`).

With an active sprint, the board, the backlog and the done group (decision 3) never overlap and together cover every task in no sprint or the active sprint. Without an active sprint, the backlog is a subset of the board, which is intended (spec project-board, "Backlog").

### 3. Done tasks outside sprints are their own view

`GET .../tasks?view=backlog_done` returns `kept.roots.in_backlog` in the done column, ordered `completed_at DESC, id DESC`. The backlog screen loads it alongside `view=backlog`, so the collapsed "Done (n)" group can show its count without another request.

- *Alternative: include done tasks in `view=backlog` and split them in the client.* Rejected: the backlog view would no longer match the spec's backlog, and the done list could not later be paginated on its own.
- *Alternative: load the done list only when the group is expanded.* Rejected: the count shown while collapsed would need its own endpoint or header.

### 4. Placement requires a column and can change the sprint in the same operation

`Board#place(task, status_id:, position:, sprint_id: <unchanged>)` rejects a missing column (the presence validation from decision 1) and optionally sets the sprint before inserting at the position, all inside the existing project lock. `PATCH .../placement` accepts an optional `sprint_id`. "To board" from the backlog sends the active sprint's id with the chosen column.

- *Alternative: placement joins the active sprint implicitly.* Rejected: the task page's column control also uses placement, and changing the column of a task in a planned sprint would pull it into the active sprint.
- *Alternative: two requests (set sprint, then place).* Rejected: not atomic; a failure between them leaves the task in the sprint at the wrong position, or in the backlog with a new column.

### 5. "Move to backlog" uses the existing sprint endpoint

The board's "Move to backlog" calls `PATCH .../tasks/:id/sprint` with `sprint_id: null`; the task keeps its column. Because `sprint_id` is part of the `acts_as_list` scope, changing it moves the task to the bottom of its column in the new scope and closes the gap in the old one. Tests cover that both scopes stay contiguous. Moving a sprint task to another sprint from the sprints screen uses the same endpoint.

### 6. Task creation takes an explicit `sprint_id`, replacing `outside_sprint`

`POST .../tasks` accepts `sprint_id`. When the parameter is present it wins (`null` means no sprint). When it is absent, a task created on a named column joins the active sprint and a task created without a column joins no sprint, which keeps today's board and backlog add fields working without sending a sprint. `outside_sprint` is removed. The UI never sends it, and `sprint_id: null` says the same thing. The sprint is validated by the existing `Task` checks (same project, not archived).

### 7. Deleting a column moves its tasks to the first remaining column

`Board#delete_column` moves the column's tasks, one at a time in their current order, to the first remaining column (by position), keeping their sprint. Changing `status_id` changes the `acts_as_list` scope, so each lands at the bottom of the target column within its own sprint. Done is always last, so the target is the done column only when it is the only one left. The tasks then get a completion time from `Task#track_completion`, as for any move into done.

### 8. Sprint task list as a nested resource, with carry-over info

`GET /api/projects/:project_id/sprints/:sprint_id/tasks` returns the sprint's root, non-archived task cards, done ones included, in the order from decision 2. `@project.sprints.find` gives the 404 for a sprint of another project. It sits with the existing nested `activation` and `archival` sprint resources.

Each card in this response also carries `carried_to: { id, title } | null`: the sprint of the task's most recent copy (the newest task whose `origin_task_id` is this task). It comes from one query over the listed ids, so there are no per-row queries. Other card endpoints are unchanged.

- *Alternative: `GET .../tasks?view=sprint&sprint_id=`.* Workable, but the views are project-wide lists. A sprint's tasks belong to the sprint resource.
- *Alternative: embed tasks in the sprints index.* Rejected: it loads every sprint's tasks, archived ones included, for a screen that shows a few sections.

### 9. Client

- **Types and board store:** `TaskCard.status_id` becomes `Id`, and the board store's `status_id !== null` checks go away. A card is on the board when `card.sprint_id === (activeSprint?.id ?? null)`.
- **Backlog store:** loads `backlog` and `backlog_done`, gets `moveToSprint(taskId, sprintId)`, and `placeOnColumn` sends the active sprint's id.
- **Backlog screen:**
  - Each row shows its column with `StatusDot`.
  - The move menu lists the open sprints from the sprints store, and the board columns only when `board.activeSprint` is set.
  - The done group is a native `<details>` below the list. Its `<summary>` holds only the "Done (n)" text, so `<details>` is accessible here.
- **Sprints store:** keeps tasks per sprint (`Map<sprintId, TaskCard[]>`), loads a section's tasks when it is first expanded, and supports adding a task to a sprint and moving a task to another sprint or to the backlog.
- **Sprints screen:**
  - Sections use a heading containing a disclosure button (`aria-expanded`, `aria-controls`) rather than `<details>`/`<summary>`. The header also holds "Make active" and "Archive", and interactive controls inside `<summary>` are not reliably accessible.
  - Planned sprints start expanded and the active sprint starts collapsed (its tasks are on the board).
  - Done rows get a "Done" chip and muted styling. Carried-over rows get a "Carried to <sprint>" chip, so neither state is shown by colour alone.
  - The archived list keeps its existing `<details>`.
- **Other screens:** the task page's column control drops the "Backlog" choice. `BoardList`'s "Move to backlog" is shown only with an active sprint.
- **Leftover "backlog" buckets:**
  - `Sprint#task_counts` no longer produces a `"backlog"` key, and the sprints screen drops that row.
  - `Statistics#overview` drops its column-less group. No spec change: the `statistics` spec never mentioned it.

## Risks / Trade-offs

- **[Visible move of old backlog items]** After the migration, column-less tasks with no sprint land in the first column. In projects without an active sprint they therefore appear on the board. → This follows from the confirmed rules (option A + every task has a column). Call it out in the release notes. In projects with an active sprint they stay off the board, in the backlog.
- **[Column-less tasks in a sprint]** Tasks in the active sprint that were "moved to backlog" under the old rules (no column, still in the sprint) move to the first column and reappear on the board. → Acceptable: under the new rules "Move to backlog" means leaving the sprint. Such tasks can be moved again.
- **[Breaking API]** Placement with `status_id: null` is rejected, and `outside_sprint` is gone. → The SPA is the only client and ships with the backend. Request tests cover the new behavior.
- **[Done list grows without bound]** `view=backlog_done` returns every done task in no sprint and is loaded with the backlog. → Cards are small and old tasks can be archived. Paginate the view if it becomes a problem; it is a separate view for that reason (decision 3).
- **[Order across columns]** Backlog and sprint sections mix columns, and positions are per column and sprint, so there is no single manual order. → Lists are ordered by column, then position. Manual reordering is out of scope.
- **[Per-section requests on the sprints screen]** One request per expanded sprint. → Projects have a handful of open sprints, and sections load lazily.

## Migration Plan

1. Migration, in SQL: for each project, move tasks with `status_id IS NULL` to the project's first status (lowest `position`). For each target (column, sprint, parent) scope, number them after the current maximum position, in their old order (`sprint_id, position, id`). Then `change_column_null :tasks, :status_id, false`. Raise if a project with such tasks has no statuses; the column rules forbid that, so it would mean corrupt data.
2. Deploy the migration with the backend and client changes in one release.
3. Rollback: revert the code and run the down migration, which only makes `status_id` nullable again. Moved tasks stay on the first column, which is still a valid, visible state under the old rules.
