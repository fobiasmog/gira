## 1. Data model <!-- goalner:TEST-13 -->

- [x] 1.1 Add the migrations for the `openspec_changes` table (unique `[project_id, name]`, foreign keys to `projects`, `milestones` and `users`) and the nullable, indexed `tasks.openspec_change_id` (design decision 1); verify that `bin/rails db:migrate` and a rollback succeed and that `db/schema.rb` shows both. <!-- goalner:TEST-20 -->
- [x] 1.2 Add `OpenspecChange` (name format and length, uniqueness within the project, `milestone`, `imported_by`, `tasks`) and `Task belongs_to :openspec_change, optional: true`; verify with model tests for valid and invalid names and for the same name in two projects. <!-- goalner:TEST-27 -->

## 2. Reading tasks.md <!-- goalner:TEST-14 -->

- [x] 2.1 Add `OpenspecChange::TasksText`, which parses sections, items, item indentation, descriptions, introductions, the "Tasks" section and line numbers, and cuts long titles at a word boundary with an ellipsis, moving the whole line into the description (design decision 6); verify with unit tests for every scenario of the spec requirement "Reading tasks.md", plus a CRLF text and a UTF-8 text. <!-- goalner:TEST-21 -->
- [x] 2.2 Parse and render marks: read `<!-- goalner:KEY -->` by the number after the last hyphen, add or replace marks at line ends, and check the boxes of done items, leaving every other byte as sent (design decisions 2 and 3); verify with unit tests in which a text without marks comes back unchanged apart from the added marks, a changed short name is replaced, and CRLF endings survive. <!-- goalner:TEST-28 -->

## 3. Import <!-- goalner:TEST-15 -->

- [x] 3.1 Add `OpenspecChange::Import` validation: the name, artifacts other than `tasks`, the limits (100,000 characters, 50 cards, 500 subtasks) and the mark rules (unknown task, other change, card or subtask in the wrong place, repeated mark), each error naming its line; verify with tests for each refusal scenario in the spec. <!-- goalner:TEST-22 -->
- [x] 3.2 Create and update: find or create the change, find, recover or create its milestone, upsert cards and subtasks in text order (first column, active sprint or none, milestone on cards only, bottom of the column), update titles and descriptions, and re-parent moved items; verify with tests for the first import, the active and no-sprint cases, a renumbered item keeping its assignee and comments, a title edited in Goalner, a moved item and a deleted milestone. <!-- goalner:TEST-29 -->
- [x] 3.3 Archive tasks whose marks are gone (subtasks before their card), and treat a mark of an archived task as no mark; verify with tests for a removed item, a removed section and an archived mark. <!-- goalner:TEST-33 -->
- [x] 3.4 Completion forward only: complete checked items, check done items in the returned text, move cards whose items are all done to the done column, never reopen, and refuse an unmarked text for a change with live tasks with 409 `keys_missing` (design decision 4); verify with tests for "Checked in the text", "Done in Goalner", "Milestone progress" and "Lost write-back". <!-- goalner:TEST-35 -->
- [x] 3.5 Run the import in one transaction under `project.with_lock`, store the marked text, and stamp `imported_by` and `imported_at`; verify with a test in which a bad mark on the last line leaves task, milestone and change counts unchanged. <!-- goalner:TEST-37 -->

## 4. API <!-- goalner:TEST-16 -->

- [x] 4.1 Add the routes and `Api::Projects::OpenspecChangesController` (`create`, `show` by name) with token access, the response shape of design decision 7, and 201, 200, 404, 409 and 422; verify with controller tests for every scenario of "Import a change" and "Read a change", including an archived project. <!-- goalner:TEST-23 -->
- [x] 4.2 Add `openspec_change` to task cards and details without extra queries per task; verify with controller tests for "Card of a change" and "Ordinary task", and that the board and `assigned` views name the change. <!-- goalner:TEST-30 -->
- [x] 4.3 Tokens: read-write tokens import, read-only tokens only read, and an agent's token makes the agent the creator, with no email sent; verify with request tests for the two new `api-tokens` scenarios and an agent token, using `assert_no_enqueued_emails`. <!-- goalner:TEST-34 -->
- [x] 4.4 Carried-over cards; verify with a model test that a carried-over copy belongs to no change and has no subtasks, and that a re-import updates the original. <!-- goalner:TEST-36 -->
- [x] 4.5 Look tasks up by id or key in the placement, sprint, label, subtasks, completion and comments controllers (design decision 8); verify with controller tests for every scenario of the `tasks` requirement "Name a task by id or key in every task request", and that ids still work. <!-- goalner:TEST-38 -->

## 5. API document and MCP <!-- goalner:TEST-17 -->

- [x] 5.1 Document `importOpenspecChange` and `showOpenspecChange` in `docs/openapi.yaml`, with examples, every required error response, the 409 `keys_missing` body with `tasks`, `openspec_change` on the task schemas, and the agent's loop in the import's description; verify that `bin/openapi-verify` passes. <!-- goalner:TEST-24 -->
- [x] 5.2 Verify with an MCP test that the tool list contains `importOpenspecChange` (not read-only) and `showOpenspecChange` (read-only), and that a read-only connection sees only the latter. <!-- goalner:TEST-31 -->
- [x] 5.3 Type `task_id` as an id or a key on every task sub-route in `docs/openapi.yaml`; verify that `bin/openapi-verify` passes and, with an MCP test, that `completeSubtask` accepts `TEST-21`. <!-- goalner:TEST-39 -->

## 6. Web client <!-- goalner:TEST-18 -->

- [x] 6.1 Add `openspec_change` to the task card type, and the archive dialog warning listing each OpenSpec change with its unfinished cards, in English and Russian; verify with frontend tests for a sprint with unfinished OpenSpec cards and one whose OpenSpec cards are all done. <!-- goalner:TEST-25 -->

## 7. Documentation and dogfooding <!-- goalner:TEST-19 -->

- [x] 7.1 Add an "OpenSpec changes" section to the README: importing, saving the returned text, the marks, the agent's loop and the known limitations; verify that it matches the API document. <!-- goalner:TEST-26 -->
- [x] 7.2 Adopt this change's hand-made cards: with `bin/rails runner` on the dev instance, create the `add-openspec-changes` change for TEST with its existing milestone and the current text, and link its cards and subtasks; then import this `tasks.md` through MCP and verify HTTP 200, no new task, and a returned text equal to the file apart from checkboxes. Needs the separate MCP UTF-8 fix first. <!-- goalner:TEST-32 -->
