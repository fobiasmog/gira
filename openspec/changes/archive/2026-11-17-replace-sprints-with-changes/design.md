# Design

## Context

See proposal.md for why. The current state that shapes the approach:

- **Sprints.** `Sprint` has `starts_on`, `ends_on`, `active` (one per project, partial unique index, `Sprint#activate!` under `project.with_lock`) and `archived_at`. `Sprint#carry_over_to` copies open root tasks and links each copy through `tasks.origin_task_id`. `Project#active_sprint` drives the board (`BoardsController`, `TasksController#index` with `view=board`), task creation on a column (`TasksController#create`) and the import (`OpenspecChange::Import#upsert_tasks!`).
- **Milestones.** `Milestone` is soft-deleted and recoverable. Tasks carry `milestone_id`, and `OpenspecChange` requires a milestone, which the import creates or recovers.
- **OpenSpec changes.** `OpenspecChange` has `name` (unique per project), `milestone_id`, `tasks_text`, `imported_by_id` and `imported_at`, and tasks carry `openspec_change_id`. `OpenspecChange::Import` matches marks to tasks by number, archives tasks of the change whose marks are gone, and raises `KeysMissing` when the change has kept tasks and the text has no marks. `OpenspecChange::TasksText` parses and renders the text.
- **Positions.** `Task` uses `acts_as_list` scoped by `project_id, status_id, sprint_id, parent_id`, so each sprint has its own positions within a column. `Board#place` takes an optional `sprint_id` so that a backlog task can be put on the board and into the active sprint in one move.
- **Backlog.** `Task.in_backlog` is `sprint_id: nil`. `TasksController#index` has the views `backlog` and `backlog_done`. The web client has `BacklogPage`, and `BoardList` offers "move to backlog" during a sprint.
- **MCP.** The MCP server builds one tool per operation of `docs/openapi.yaml`, named by its `operationId`, so renaming and removing operations renames and removes tools with no MCP code. A running server only sees the change after a restart, and clients must reconnect.
- **Web client.** `projectSections` (router/sections.ts) lists Board, Backlog, Sprints, Milestones and the rest. The board store loads `GET /board` and keeps `activeSprint`; `sprintSummary` computes days left; `TaskDetails` has milestone and sprint pickers.

## Goals / Non-Goals

**Goals:**
- One model for a unit of work. A change is what the board shows, what groups tasks, what shows progress and what an import updates.
- Several boards side by side, with no active state to keep consistent.
- Leave the stage-2 fields (idea, phase, thread) room on the same record without designing them now.

**Non-Goals:**
- Keeping old API paths, operation ids or MCP tool names working. There is no production instance and the only clients are this repository's web client and its own agents.
- Keeping sprints or milestones of the development database. Only OpenSpec changes and their tasks are carried over.
- Reopening an archived change, or moving an archived change's tasks in bulk.

## Decisions

### 1. One `changes` table replaces `sprints` and `openspec_changes`

`changes`:
- `project_id` (foreign key, not null) and `name` (not null), with a unique index on `[project_id, name]` where `archived_at IS NULL`;
- `archived_at`;
- `tasks_text` (text), `imported_by_id` (foreign key to `users`) and `imported_at`, all nullable until the first import;
- timestamps.

The model is `Change`. `OpenspecChange::Import` and `OpenspecChange::TasksText` move to `Change::Import` and `Change::TasksText` and keep their logic, minus milestones and sprints (decision 4).

Alternatives:
- *Keep `openspec_changes` as a 0..1 child of a change.* Two records for one thing, both called "change" in code, with nothing to keep on the child that the parent cannot hold. The user confirmed at most one OpenSpec change per change, so the child only adds a join.
- *Rename `sprints` in place.* Most of its columns go and the uniqueness rule differs, and nothing in it needs to survive (non-goal). A new table is simpler to migrate and review.
- *Name unique across all changes of a project, archived included.* OpenSpec allows a name to come back after its change is archived (the archive folder is dated), so the index only covers open changes.

### 2. `tasks.change_id` replaces `sprint_id` and `openspec_change_id`

Every task of a change, root or subtask, carries `change_id`. A subtask always has its parent's change: `Task` sets it from the parent when the subtask is created or when the parent moves, so lists, archiving and import checks can filter on one column. `acts_as_list` is scoped by `project_id, status_id, change_id, parent_id`, so each change keeps its own positions in a column, as each sprint did.

`milestone_id`, `origin_task_id`, `sprint_id` and `openspec_change_id` are dropped, with their indexes and foreign keys.

Alternatives:
- *Keep two columns: one for where a task is shown and one for the import's change.* That allows a card to sit in one change and be updated by another's import, which the specs rule out (spec `changes`, "Tasks in a change").

### 3. `tasks.in_tasks_md` marks what the import owns

A boolean column, default false, set to true for every task the import creates or matches by a mark (including a task added by hand and then marked, which the import adopts). The task JSON exposes it as `in_tasks_md`. It answers three questions without parsing the stored text:
- which tasks a re-import may archive (marked before, not marked now);
- whether `KeysMissing` applies (the change has kept tasks with `in_tasks_md` and the text has no marks);
- whether a card may move to another change (spec `changes`, "Tasks in a change") and whether the changes screen offers its move menu.

Alternatives:
- *Derive it from the marks in `tasks_text`.* Correct, but every task list would need the change's text parsed, and a task's own JSON would depend on another record's text.
- *"Created by an import".* Wrong for adopted tasks, and wrong for a marked task whose mark is later removed (it is archived anyway, but the flag would say otherwise in between).

### 4. Import changes

- **Which change.** The import looks for the project's open change of the name (`changes.where(archived_at: nil).find_or_initialize_by(name:)`). A new record answers 201, an existing one 200, whether or not it was imported before.
- **Cards.** New cards get `change: @change` instead of `sprint: active_sprint` and `milestone:`. The card title keeps its `<change>: ` prefix, because cards also show outside their change's board (dashboard, an agent's assigned tasks, notifications).
- **Marks.** A mark is valid when it names a task with `change_id == change.id`, whether the import created it or a person did.
- **Archiving.** Tasks with `in_tasks_md` whose marks are gone are archived, as today; tasks without it are never touched.
- **Read back.** `Change#current_tasks_text` keeps the checkbox refresh of `OpenspecChange#current_tasks_text`, and returns `nil` for a change never imported.

### 5. API and operation ids

| Before | After |
|---|---|
| `GET /sprints?view=all\|available\|archived` (`listSprints`) | `GET /changes?view=open\|archived` (`listChanges`) |
| `POST /sprints` with dates, `activate`, `carry_over` (`createSprint`) | `POST /changes` with `name` (`createChange`) |
| `POST /sprints/{id}/activation` (`activateSprint`) | removed |
| `POST /sprints/{id}/archival` with `carry_to_sprint_id` (`archiveSprint`) | `POST /changes/{change}/archival` (`archiveChange`) |
| `GET /sprints/{id}/tasks` (`listSprintTasks`) | `GET /changes/{change}/tasks` (`listChangeTasks`) |
| `GET /openspec_changes/{name}` (`showOpenspecChange`) | `GET /changes/{change}` (`showChange`) |
| `POST /openspec_changes` (`importOpenspecChange`) | unchanged path and id |
| `PUT /tasks/{task}/sprint` (`setTaskSprint`) | `PUT /tasks/{task}/change` with `change_id` (`setTaskChange`) |
| `GET /board` (`showBoard`) | `GET /board?change_id=` |
| `GET /tasks?view=backlog\|backlog_done` | removed; `view=board` takes `change_id` |
| milestone operations (5) | removed |

All paths are under `/api/projects/{project_id}`. `{change}` accepts an id or, for an open change, its name; a value made only of digits is an id (spec `changes`, "Open a change"). The import keeps its path because it imports an OpenSpec artifact, which is narrower than creating a change.

Responses:
- a change: `id`, `name`, `archived_at`, `task_counts` (roots only, per column and total), and on `showChange` also `cards`, `tasks_text`, `imported_by`, `imported_at`;
- a task: `change_id`, `change` (`{id, name}` or `null`) and `in_tasks_md`, in place of `sprint_id`, `sprint`, `milestone_id`, `milestone` and `openspec_change`;
- the board: `change` (`{id, name}` or `null`) and `changes` (open changes, newest first, with `task_counts`), in place of `active_sprint`.

`Board#place` loses its `sprint_id` argument: placing never changes a task's change.

### 6. Web client

- **Address.** `/projects/:pid/board` shows the default tab, `/projects/:pid/board/changes/:name` a change and `/projects/:pid/board/other` the other tasks; `/list/...` mirrors them for the list layout. The `changes/` segment keeps a change named `other` addressable.
- **Board store.** Loads `GET /board?change_id=` for the shown tab, and keeps `change` and `changes` from the response for the tabs and the summary. Creating a task on a column sends the shown change's id.
- **Components.** `ChangeTabs` (a tab list above both layouts), `ChangeSummary` (replaces the sprint summary; no dates), `NewChangeDialog` (name field that lowercases and turns spaces into hyphens as you type, server errors inline), `ArchiveChangeDialog` (counts root tasks not in the done column).
- **Screens.** `ChangesPage` replaces `SprintsPage`, without dates, activation or carry-over. `BacklogPage`, `MilestonesPage`, `MilestonePage`, the backlog and milestone stores and APIs, and `sprintSummary`/`openspecWork` go. `BoardList` loses "move to backlog". `TaskDetails` swaps the sprint picker for a change picker (open changes and "No change"; disabled with an explanation when `in_tasks_md`) and drops the milestone picker.
- **Navigation.** `projectSections`: Board, Changes, Members, Agents, Archive, Settings.

### 7. Migration of existing data

One migration, run on the development database only:
1. create `changes`; add `tasks.change_id` and `tasks.in_tasks_md`;
2. insert one change per `openspec_changes` row (same project, name, `tasks_text`, importer and import time);
3. set `change_id` on tasks from `openspec_change_id`, then on remaining subtasks from their parent; set `in_tasks_md` where `openspec_change_id` was set;
4. renumber positions per `project_id, status_id, change_id, parent_id`, in the old order (`position`, then `id`), since the new scope merges tasks that were in different sprints;
5. drop the old columns, then `openspec_changes`, `sprints` and `milestones`.

It is irreversible (`raise ActiveRecord::IrreversibleMigration` in `down`).

## Risks / Trade-offs

- [Agents or clients still call the old tools] → The MCP tool list changes on restart. The README's agent section and the project memory note are updated in the same change, and the old tools fail loudly as unknown tools instead of doing something else.
- [A change's name is taken while an agent works on an archived one] → Importing an archived change's marked text into a new open change of the same name is refused with a validation error naming a line (spec `openspec-changes`, "Import after archiving"), so nothing is duplicated silently.
- [A card that agents work on cannot be moved] → Intended: tasks.md owns it. Removing its section from tasks.md and re-importing archives it, and the task page says why the change picker is disabled.
- [Large diff across the whole stack] → The tasks are ordered so that the database and models land first, then the API with its tests and `docs/openapi.yaml`, then the web client; each section ends green.
- [Losing development data] → Sprints and milestones of the development database are dropped by design. Back up with `pg_dump` before migrating if they matter.

## Migration Plan

1. Back up the development database (optional).
2. Deploy code and run the migration.
3. Restart the MCP server and reconnect MCP clients (`/mcp` in Claude Code) so they see the new tools.
4. No rollback: restore the backup and check out the previous commit instead.
