## 1. Data model and migration

- [x] 1.1 Add the migration of design decision 7: create `changes` (partial unique index on `[project_id, name]` where `archived_at IS NULL`), add `tasks.change_id` and `tasks.in_tasks_md`, copy each OpenSpec change and its tasks over, renumber positions per `project_id, status_id, change_id, parent_id`, then drop `sprint_id`, `milestone_id`, `origin_task_id`, `openspec_change_id`, `openspec_changes`, `sprints` and `milestones`; verify that `bin/rails db:migrate` succeeds on the development database, that `db/schema.rb` has `changes` and none of the dropped tables, and that the cards of `add-openspec-changes` belong to a change of that name with `in_tasks_md` set.
- [x] 1.2 Add `Change` (name format and length, uniqueness among the project's open changes, `archive!` that leaves an archived change as it is, root-only `task_counts`, `current_tasks_text` returning `nil` when never imported); verify with model tests for every scenario of "Changes in a project" and "Archive twice".
- [x] 1.3 Update `Task`: `belongs_to :change`, the change must be open and of the same project when set, a subtask takes its parent's change on creation and when the parent moves, a card with `in_tasks_md` cannot change its change, and `acts_as_list` scoped by `change_id`; remove the sprint, milestone and origin associations and validations; verify with model tests for every scenario of "Tasks in a change".
- [x] 1.4 Remove `Sprint`, `Milestone` and `OpenspecChange`, `Project#active_sprint` and the project associations, and the `sprint_id` argument of `Board#place`; verify that `bin/rails test test/models` passes with the board tests updated.

## 2. Import

- [x] 2.1 Move the import and the parser to `Change::Import` and `Change::TasksText`; work on the project's open change of the name (create it and answer 201, or answer 200), put new cards in the change with no milestone and no sprint, and count limits in sections and items (design decision 4); verify with import tests for "First import", "Change created by hand", "Cards in their change", "Change progress", "Invalid name" and "Too many items".
- [x] 2.2 Set `in_tasks_md` on every created or matched task, accept marks of tasks with the change's `change_id`, archive only `in_tasks_md` tasks whose marks are gone, and raise `KeysMissing` only when kept `in_tasks_md` tasks exist and the text has no mark; verify with import tests for "Adopting a task added by hand", "Task added by hand", "Lost write-back", "Import after archiving" and the existing re-import scenarios.

## 3. API

- [x] 3.1 Add `Api::Projects::ChangesController`: `index` (`view=open|archived`, newest first or most recently archived first, task counts), `create` (201, 422, 404 for an archived project) and `show` (by id, or by the open change's name when the value is not all digits, with cards and the OpenSpec fields); open all three to tokens; verify with controller tests for every scenario of "Create a change", "Change lists and statistics", "Open a change" and "Read a change".
- [x] 3.2 Add `Changes::ArchivalsController` and `Changes::TasksController`; verify with controller tests for "Archive with unfinished cards", "Archive twice", "Tasks of a change" and "Change of another project".
- [x] 3.3 Replace `Tasks::SprintsController` with `Tasks::ChangesController` (`change_id`, `null` takes the task out); verify with controller tests for every scenario of "Tasks in a change", including the 422 for a card of tasks.md and subtasks following their card.
- [x] 3.4 Board and tasks: `BoardsController` takes `change_id` (404 for an archived change or one of another project) and answers `change` and `changes`; `TasksController#create` takes `change_id`, `index` drops the backlog views and filters `view=board` by `change_id`, and `milestone_id` is no longer permitted; `PlacementsController` drops `sprint_id`; verify with controller tests for "Board of a change", "Board snapshot", "Create a task in a change or in none" and "Edit a task's fields".
- [x] 3.5 `TaskSerializer`: `change_id`, `change` and `in_tasks_md` in place of the sprint, milestone and OpenSpec change fields, without a query per task; verify with tests for every scenario of "Tasks name their change", and a query-count assertion on the board.
- [x] 3.6 Remove the sprint, milestone and `showOpenspecChange` routes, controllers and serializers, keeping `POST /openspec_changes`; verify that `bin/rails routes` lists no sprint or milestone route and that a request to a removed path gets the JSON 404 envelope.
- [x] 3.7 Tokens: update the endpoint list; verify with request tests for the `api-tokens` scenarios "Changes" and "Changes with a read-only token", and that the existing token tests pass.

## 4. API document and MCP

- [x] 4.1 Update `docs/openapi.yaml` as in design decision 5: the change operations and schema, the board and task schemas, the removed operations, examples, and an import description that tells agents to create the change or let the import create it; verify that `bin/openapi-verify` and the examples contract test pass.
- [x] 4.2 Verify with MCP tests that the tool list has `listChanges`, `createChange`, `showChange`, `archiveChange`, `listChangeTasks`, `setTaskChange` and `importOpenspecChange`, has no sprint, milestone or `showOpenspecChange` tool, and that `setTaskChange` with `change_id: null` takes a task out of its change.

## 5. Web client: board

- [x] 5.1 API modules and types: add `api/changes.ts`, `change`, `changes` and `in_tasks_md` in the types; remove `api/sprints.ts`, `api/milestones.ts`, and the backlog and milestone stores; verify that `npm run typecheck` passes.
- [x] 5.2 Router and navigation: `/board`, `/board/changes/:name`, `/board/other` and the `/list` variants; remove the backlog, sprints and milestone routes; sections Board, Changes, Members, Agents, Archive, Settings; verify with frontend tests for the routes and `sectionOf`.
- [x] 5.3 Board store and `ChangeTabs`: load the shown tab, default tab, the message for a change that is not open, a tab list for assistive technology, and new tasks created in the shown change; verify with frontend tests for the default-tab rules and a system test for "Switch change", "Reload", "Archived change in the address" and "Add a task to a change's board".
- [x] 5.4 `ChangeSummary` in place of the sprint summary, and remove `sprintSummary`; verify with a frontend test for the progress numbers and a system test for "Change in progress" and "Other tasks".
- [x] 5.5 `ArchiveChangeDialog`: the count of root tasks not done and the warning, confirmation, and the default tab after archiving from the board; remove `openspecWork`; verify with a frontend test for the count and system tests for every scenario of "Archiving a change".
- [x] 5.6 `NewChangeDialog`: lowercase and hyphens as you type, the format hint, server errors inline, and the new tab after creating from the board; verify with a frontend test for the name conversion and system tests for "Name taken" and "From the board".

## 6. Web client: screens

- [x] 6.1 `ChangesPage` in place of `SprintsPage`: open changes as sections with counts, archive action, add field and move menu (none for a card with `in_tasks_md`), a "New change" action, and archived changes collapsed below; verify with system tests for every scenario of "Changes screen".
- [x] 6.2 Task page: a change picker (open changes and "No change", disabled with an explanation for a card with `in_tasks_md`) in place of the sprint picker, and no milestone picker; verify with a system test in `test/system/task_page_test.rb`.
- [x] 6.3 Remove `BacklogPage`, `MilestonesPage`, `MilestonePage` and the board list's "move to backlog"; add the English and Russian texts for the new screens and drop the unused ones; verify that `npm test`, `npm run typecheck` and `npm run policy` pass.
- [x] 6.4 Update the system tests that use sprints, milestones or the backlog (`sprints_milestones_test`, `backlog_test`, the board tests, `app_shell_test` with the Changes link, `accessibility_test` with the new change dialog, the components fixture); verify that `bin/rails test:system` passes after `npm run build`, apart from the two failures known on this machine.

## 7. Documentation and dogfooding

- [x] 7.1 README: the API list (changes instead of sprints and milestones), the OpenSpec section (cards in their change, adopting tasks added by hand, no carry-over notes), and the agent workflow (create a change or let the import create it; archive it when done); verify that it matches `docs/openapi.yaml`.
- [x] 7.2 Check the whole flow in the running app (this change itself is not tracked on the board): restart the MCP server and reconnect, then through MCP create a change in TEST, import a small sample `tasks.md` into it and import the returned text again; verify HTTP 200 both times and no new task the second time, that the cards show under the change's tab on the board, and that archiving the change from the board removes its tab.
- [x] 7.3 When archiving this change: update the Purpose of the `projects`, `project-board` and `openspec-changes` specs, and delete the emptied `sprints` and `milestones` spec folders; verify that `openspec validate --specs --strict` passes.
