## 1. Data model and migration

- [ ] 1.1 Add the migration of design decision 11: `changes.idea` and `changes.phase` (default `idea`, check constraint on the four stored values, `implementing` for changes with `tasks_text`), the tables `change_files` (unique `[change_id, path]`) and `change_events`, and `comments.change_id` with `task_id` nullable and the check `num_nonnulls(task_id, change_id) = 1`; verify that `bin/rails db:migrate` and a rollback succeed on the development database, and that `add-openspec-changes` is in `implementing`.
- [ ] 1.2 `Change`: idea length and the rule that only a change in `idea` may change its idea, no update of an archived change, `move_to!(phase, by:)` writing a `phase` event only on a real move, `phase_reported` deriving Done (design decision 2), and `waiting_for_people` for many changes in one query (design decision 8); verify with model tests for every scenario of "Idea of a change", "Phase of a change", "Change history" and "Waiting for people".
- [ ] 1.3 Add `ChangeFile` (path format, uniqueness per change) and `ChangeEvent` (kinds `phase` and `import`, actor, phase, paths); verify with model tests, including the order of a change's files: proposal, design, then specs by path.
- [ ] 1.4 `Comment`: optional `task` and `change`, exactly one of them, and `project_id` from either; verify with model tests, and that the database refuses a comment with both or neither.

## 2. Import

- [ ] 2.1 Accept `proposal`, `design` and `specs` in `Change::Import#validate_input!`: string types, the capability path format, 100,000 characters per file and at most 50 specs, errors naming the field or the key (design decision 6); verify with import tests for "Other artifacts", "Invalid capability path", "Proposal too long" and "Too many specs".
- [ ] 2.2 Store the files sent and delete the others, record an `import` event with the paths and `tasks.md`, move a change in `idea` or `exploring` to `proposed`, and create a new change in `proposed`; verify with import tests for "First import", "Change created by hand", "Import during implementation", "All the files", "Files stored", "File no longer sent", the history scenario "Import", and "All or nothing" leaving files and history unchanged.

## 3. API

- [ ] 3.1 `ChangesController`: `create` takes `idea`; add `update` (`updateChange`, `idea` and `phase` under the project's lock, 422 for `done`, an unknown phase, a fixed idea or an archived change); verify with controller tests for "Create", "Create with an idea", "Edit before exploring", "Fixed once exploring starts", "Idea too long", "Agent moves the phase", "Back to an earlier phase", "Done cannot be chosen", "Archived change" and "Same phase".
- [ ] 3.2 `ChangeSerializer`: `idea`, `phase` (reported), `waiting_for_people` in lists and in the detail, and `history` and `files` (paths and lengths, no text) in the detail; verify with tests for "Change statistics", "Phase and waiting in the list", "Idea, phase and history", "Done" and "Out of Done", and a query-count assertion on the changes list and the board.
- [ ] 3.3 Add `Changes::FilesController#show` (`showChangeFile`, `?path=`, any change of the project); verify with controller tests for "Files stored", "Unknown path" and the file scenario "Archived change".
- [ ] 3.4 Add `Changes::CommentsController` (`listChangeComments` oldest first, `createChangeComment` with JSON or multipart, refused on an archived change); verify with controller tests for "Thread order", "Agent through MCP", the comment scenario "Archived change", "Attachment on a change comment", "Agent asked" and "Answered".
- [ ] 3.5 Edit, delete and download comments of changes: `Api::CommentsController#set_comment` and `FilesController#visible?` through `Comment#project_id`; verify with tests for "Delete a comment on a change", "Edit someone else's comment" on a change comment, and an attachment of a change comment that a member downloads and a non-member gets 404 for.
- [ ] 3.6 Open the new endpoints to tokens; verify with request tests for the `api-tokens` scenarios "Change thread, phase and files" and "Change thread with a read-only token", and that the existing token tests pass.

## 4. API document and MCP

- [ ] 4.1 Update `docs/openapi.yaml` as in design decision 9: `updateChange`, `showChangeFile`, `listChangeComments`, `createChangeComment`, the change schema (`idea`, `phase`, `waiting_for_people`, `history`, `files`), the import's artifacts, and descriptions that tell agents to import every file of the change folder, to ask their questions in the thread, and to move the phase; verify that `bin/openapi-verify` and the examples contract test pass.
- [ ] 4.2 Verify with MCP tests that the tool list has `updateChange`, `showChangeFile`, `listChangeComments` and `createChangeComment`, that `updateChange` with an agent token moves a change and records the agent in its history, and that `createChangeComment` works with a JSON body.

## 5. Web client

- [ ] 5.1 Types and API modules: the new change fields, `history` and `files`, `updateChange`, `showChangeFile`, and the change comment calls; verify that `npm run typecheck` passes.
- [ ] 5.2 Route `/projects/:pid/changes/:ref` and `ChangePage` header: name, phase stepper with current and passed marked in text, card counts with a link to the board tab, phase menu and Archive for an open change, the not-found message, and a read-only page for an archived change; verify with a route test and system tests for "Phase menu", the page scenario "Archived change" and "Unknown change".
- [ ] 5.3 The idea on the page: formatted, with an edit form while the change is in Idea; verify with a system test for "Idea fixed" and for editing the idea of a change in Idea.
- [ ] 5.4 The thread: comments and history lines merged by time, with `CommentItem` and `CommentForm` on change callbacks, agent markers, and history lines in the viewer's language; verify with a frontend test for the merge order and system tests for "Answer in the thread" and "History in the thread".
- [ ] 5.5 The files: a tab per file plus `tasks.md`, loading each file when its tab is shown, formatted or as source, and the last importer and time; verify with system tests for "Review a proposal", "Source of a file" and the `markdown-content` scenario "Table in a change file".
- [ ] 5.6 Board: phase and waiting marker in `ChangeTabs`, and the phase and the link to the change page in `ChangeSummary`; verify with system tests for the tabs scenario "Phase and waiting marker" and "Change in progress".
- [ ] 5.7 Changes screen: phase and waiting marker in each section header, names linking to the change page (open by name, archived by id); verify with a system test for the changes screen scenario "Phase and waiting marker".
- [ ] 5.8 `NewChangeDialog`: an idea field sent as `idea`; verify with a system test for "With an idea".
- [ ] 5.9 English and Russian texts for the new screens and lines, and the change page in the accessibility test; verify that `npm test`, `npm run typecheck` and `npm run policy` pass, and that `bin/rails test:system` passes after `npx vite build --mode test`, apart from the two failures known on this machine.

## 6. Documentation and dogfooding

- [ ] 6.1 README: the changes API (idea, phase, thread, files), the OpenSpec section (every file of the change folder, `showChangeFile`, the phase move on import), and the agent workflow (read the idea, move to Exploring, ask in the thread and wait, import every file, move to Implementing when told, work the cards); verify that it matches `docs/openapi.yaml`.
- [ ] 6.2 Check the flow in the running app: restart the MCP server and reconnect, then create a change with an idea in TEST, move it to Exploring and ask a question through MCP, see the waiting marker on the board, answer on the change page, import a proposal, a spec and a tasks text through MCP, and read them on the page; verify that the change is in Proposed, its history shows both moves and the import, and the marker is gone after the answer.
- [ ] 6.3 When archiving this change: update the Purpose of the `changes`, `comments` and `openspec-changes` specs to mention ideas, phases, threads and files; verify that `openspec validate --specs --strict` passes.
