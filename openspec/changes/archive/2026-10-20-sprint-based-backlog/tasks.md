# Tasks

## 1. Mandatory column

- [x] 1.1 Add a migration that moves every task with `status_id IS NULL` to its project's first status, numbering positions after the current maximum of each target (column, sprint, parent) scope in the old order (`sprint_id, position, id`), then sets `tasks.status_id` to `NOT NULL`; it raises if a project with such tasks has no statuses, and its down step only makes the column nullable again (design.md, Migration Plan); verify `bin/rails db:migrate` on the dev database leaves `Task.where(status_id: nil).count == 0` with contiguous positions per scope, `db/schema.rb` shows `null: false`, and `bin/rails db:rollback && bin/rails db:migrate` succeeds
- [x] 1.2 In `Task`, default the column to `project.first_status` on create and validate its presence; redefine `in_backlog` as `where(sprint_id: nil)` and remove `on_board`; drop the now-redundant first-column special case from subtask creation; verify `test/models/task_test.rb` cases for "created without a column lands at the end of the first column" and "clearing the column is rejected"
- [x] 1.3 Update fixtures and test helpers that create tasks without a column (e.g. the `status: nil` default in `test/controllers/api/statistics/statistics_test.rb`); verify `bin/rails test` has no failures caused by the `NOT NULL` constraint (placement-to-backlog tests are rewritten in 2.1)

## 2. Board and backlog (backend)

- [x] 2.1 Make `Board#place` reject a missing column and accept an optional `sprint_id` that is changed inside the same project lock before inserting at the position; `PlacementsController` passes `sprint_id` through; verify `test/models/board_test.rb` cases for placement without a column (task unchanged) and placement with a sprint change (contiguous positions in the old and new scope), and request tests for the project-board scenarios "Placement without a column" and "Put a backlog task on the board"
- [x] 2.2 Make `Board#delete_column` move the column's tasks in order to the first remaining column, keeping their sprint, with completion tracking when the target is the done column; verify `board_test.rb` cases for the project-board scenarios "Delete a column with tasks", "Delete the first column" and "Only the done column remains"
- [x] 2.3 Switch the board (`BoardsController#show` and `view=board`) to `kept.roots.where(sprint_id: active_sprint&.id)`, `view=backlog` to `kept.roots.in_backlog.not_done`, both ordered by column position then position, and add `view=backlog_done` ordered by `completed_at DESC, id DESC`; verify request tests for "Task on a column outside the active sprint" (the TEST-1 case), "Task in a planned sprint", "No active sprint", "Done task outside sprints", "List done tasks outside sprints" and "Board without an active sprint"
- [x] 2.4 Confirm the task sprint endpoint keeps the column when moving a task between sprints or out of a sprint, and that both `acts_as_list` scopes stay contiguous; verify request tests for the sprints scenarios "Move to another sprint", "Take a task out of its sprint", "Archived sprint" and the project-board scenario "Send to backlog", plus a `board_test.rb` position check across the scope change

## 3. Task creation, sprint task list and counts (backend)

- [x] 3.1 Accept `sprint_id` in `TasksController#create` (present wins, `null` is no sprint; absent means the active sprint when a column is named, otherwise no sprint) and remove `outside_sprint`; verify request tests for the tasks scenarios "Create without a column" (during an active sprint it stays out of the sprint), "Create in a planned sprint" and "Archived sprint", the project-board scenario "Create task during a sprint", and replace the `outside_sprint` test with `sprint_id: null`
- [x] 3.2 Add `GET /api/projects/:project_id/sprints/:sprint_id/tasks` (nested `Sprints::TasksController`) returning the sprint's root, non-archived cards in column-then-position order, each with `carried_to: { id, title } | null` computed in one query over the listed ids; verify request tests for "Tasks of a planned sprint", "Carried-over task" and the 404 for another project's sprint, and an `assert_queries_count` check that the query count does not grow with the number of tasks
- [x] 3.3 Remove the `"backlog"` bucket from `Sprint#task_counts` and the column-less group from `Statistics#overview`; verify the "Sprint statistics" request test and `test/controllers/api/statistics/statistics_test.rb` pass

## 4. Client data layer

- [x] 4.1 Update `api/types.ts` and `api/tasks.ts` (`TaskCard.status_id: Id`, `Placement` with a required column and optional `sprint_id`, `NewTask.sprint_id` replacing `outside_sprint`, the `backlog_done` view) and `api/sprints.ts` (`tasks(projectId, sprintId)` returning cards with `carried_to`); verify `npm run typecheck` passes
- [x] 4.2 Update the board store: drop the `status_id !== null` checks, decide board membership from `sprint_id` against the active sprint in a small pure helper, and make `sendToBacklog` call `setSprint(null)`; verify a `node --test` unit test for the helper (active sprint, no active sprint, other sprint) and `npm test` passes
- [x] 4.3 Update the backlog store (load `backlog` and `backlog_done`, create with `sprint_id: null`, `moveToSprint`, `placeOnColumn` sending the active sprint's id) and the sprints store (tasks per sprint loaded on first expand, add a task to a sprint, move a task to another sprint or the backlog); verify `npm run typecheck` passes (screen behavior is verified in group 5)

## 5. Client screens

- [x] 5.1 Rebuild `BacklogPage`: column dot and title per row, a move menu listing open sprints and, only with an active sprint, the board's columns, and a native `<details>` "Done (n)" group below the list; add `en`/`ru` strings; verify a new `test/system/backlog_test.rb` covering the web-client scenarios "Add a backlog task during a sprint", "Move a task into a planned sprint", "Put a task on the board", "No active sprint" and "Done tasks outside sprints", and that the i18n key-parity test passes
- [x] 5.2 Rebuild `SprintsPage` as planning sections: a heading with a disclosure button (`aria-expanded`, `aria-controls`), dates, counts, "Make active" and "Archive" in the header; a body with task rows, a "Done" chip with muted styling, a "Carried to <sprint>" chip, an add field and a move menu (other open sprints, backlog); planned sprints expanded and the active sprint collapsed on load; archived sprints in the existing `<details>`; add `en`/`ru` strings; verify `test/system/sprints_milestones_test.rb` covers "Plan a task", "Move a planned task back to the backlog", "Active sprint" and "Done and carried-over tasks in a sprint section", its existing create/activate/archive tests still pass, and `test/system/accessibility_test.rb` passes with the sections operable by keyboard
- [x] 5.3 Show `BoardList`'s "Move to backlog" only with an active sprint, and remove the "Backlog" choice from the task page's column control; verify system tests for the web-client scenarios "Move to backlog during a sprint" and the board's "No active sprint", and that `test/system/task_page_test.rb` column-change tests pass

## 6. Integration

- [x] 6.1 Run the whole suite; verify `bin/rails test`, `bin/rails test:system`, `npm test`, `npm run typecheck` and `npm run build` all pass
- [x] 6.2 On the dev server after migrating, with the sprint active: TEST-1 is listed in the backlog with its column, "To board" puts it on the board in the active sprint, and "Move to backlog" returns it; verify by doing these steps in the browser

## Workflow follow-up

- Add a release note: tasks that had no column move to their project's first column, so in projects without an active sprint they now appear on the board.
- Sync the delta specs and archive the change after review.
