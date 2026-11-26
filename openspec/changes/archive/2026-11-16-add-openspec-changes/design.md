# Design

## Context

- **Tasks.** A task has a project-wide `number` (its key is `<short_name>-<number>`, and `Task.find_by_ref!` already accepts both forms), a `parent_id` for subtasks, and `milestone_id`, `sprint_id`, `status_id` and `position`. Subtasks are listed by `id` (`Task#subtasks`), not by position. `Task#archive!` removes a task from its list and stamps `archived_at`.
- **Completion.** A subtask is done when it is in the project's done column. `CompletionsController` moves it to `Project#done_status` and back to `Project#first_status`.
- **Sprint placement.** `TasksController#create` puts a task created on a column into `Project#active_sprint`, and `Sprint#carry_over_to` copies only the attributes it names (not subtasks), linking the copy through `origin_task_id`.
- **Milestones.** `Milestone#progress` counts every non-archived task that carries the milestone, roots and subtasks alike. Milestones are soft-deleted and recoverable.
- **Locking.** Board moves and sprint activation serialise on `project.with_lock`.
- **MCP.** `mcp/lib/goalner_mcp/tool_builder.rb` builds one tool per operation of `docs/openapi.yaml`, named by its `operationId`, and `bin/openapi-verify` checks the document against the API. A new documented operation therefore becomes an MCP tool with no MCP code.
- **Tokens.** Controllers open actions to tokens with `allow_token_access`. Write actions require a read-write token.
- **Task lookups.** `TasksController` finds tasks with `Task.find_by_ref!` (id or key), but the six task sub-route controllers (`placements`, `sprints`, `labels`, `subtasks`, `completions`, `comments`) use `find(params[:task_id])`, so they take ids only.
- **MCP and UTF-8.** Found while dogfooding: Net::HTTP tags a body holding any non-ASCII byte as binary, `ApiClient` passed it on (`mcp/lib/goalner_mcp/api_client.rb`), and the MCP reply then failed to serialize, so a successful tool call whose response held non-ASCII text ended as "Internal error" although the API answered 201. Fixed separately: `ApiClient.utf8` reads every body as UTF-8, with tests over the real HTTP transport (`test/mcp/http_transport_test.rb`).

## Goals / Non-Goals

**Goals:**
- **One request, one consistent result.** An import is a single transaction, so an agent's tool call either lands completely or not at all.
- **The parser agrees with OpenSpec.** What counts as an item in Goalner is what `openspec` counts as a task, so Goalner's progress and `openspec archive`'s check agree.
- **`tasks.md` stays readable.** Marks are invisible when the Markdown is rendered and change nothing that OpenSpec parses.
- **Room for the future.** The change record is where a state, the branch and other artifacts will go when Goalner starts steering worker agents.

**Non-Goals:**
- No git access, no repository settings on projects, no background jobs.
- No new screen. The board, the milestone and the task page show the work.
- No ordering or dependencies between sections.

## Decisions

### 1. `openspec_changes` table, and a reference on `tasks`

`openspec_changes`:
- `project_id` (foreign key, not null), `name` (not null), unique on `[project_id, name]`;
- `milestone_id` (foreign key, not null);
- `tasks_text` (text, not null): the marked text as last returned;
- `imported_by_id` (foreign key to `users`, not null) and `imported_at`;
- timestamps.

`tasks.openspec_change_id` (nullable foreign key, indexed). Whether a linked task is a card or an item follows from `parent_id`, so no kind column is needed. `Sprint#carry_over_to` keeps slicing named attributes, so copies stay unlinked, as the spec requires.

Alternatives:
- *Only a milestone, no change record.* Rejected while exploring: there would be nowhere to keep the marked text, and re-imports would find the change by milestone title.
- *A `section`/`item` number column on tasks.* Not needed. The marks identify tasks, and numbers inside titles are plain text.

### 2. The marks carry the Goalner key, matched by number

The mark is `<!-- goalner:<KEY> -->` appended to the heading or item line. It is an HTML comment, so rendered Markdown hides it, and it sits at the end of the line, so OpenSpec's task pattern (`^\s*[-*]\s*\[([\sxX])\]\s*(.*)`) still matches and only the description it reports grows. Goalner reads the number after the last hyphen (`/<!--\s*goalner:[A-Z][A-Z0-9]*-(\d+)\s*-->/`) and looks it up within the change's project, so a changed short name still matches.

Alternatives:
- *Match sections and items by their OpenSpec number (`2.1`).* Rejected while exploring: inserting a task renumbers the following ones, and their history, assignees and comments would move to the wrong items.
- *A visible key such as `(TEST-21)`.* Clutters the rendered checklist and can be confused with a reference to another task in the item's text.
- *A link to the task.* Puts the instance's address into the repository.

### 3. The server writes the marks and the checkboxes

The response carries the whole text with marks inserted and checkboxes of done items checked. The client replaces `tasks.md` with it and commits. The server keeps that text in `tasks_text`, so `showOpenspecChange` can return it, with checkboxes refreshed from the current state of the subtasks.

Only two kinds of edit are made to a line: the mark is added or replaced at its end, and `[ ]` becomes `[x]` on an item's first line. Line endings (including CRLF) and every other byte stay as sent.

Alternatives:
- *Return a key map and let the client edit the file.* Every client (agents, scripts, later worker VMs) would need its own copy of the editing rules.

### 4. Completion syncs both ways, forward only

A checked item completes its subtask, and a done subtask checks its item in the returned text. Nothing reopens. With an agent ticking a subtask through MCP and committing `tasks.md` later, either side may be ahead, and a stale side can never undo progress. Reopening takes two steps: reopen the subtask in Goalner and uncheck the box.

A card moves to the done column when the import finds all its items done. Cards are otherwise moved by people and agents, and an import never takes a card out of the done column.

### 5. The import algorithm

`OpenspecChange::Import` (a plain object) runs inside `project.with_lock`, in one transaction:
1. Parse the text into sections and items (decision 6), keeping line numbers.
2. Validate: the name, the artifacts, the limits, and every mark (exists in the project, belongs to this change, card on a heading and subtask on an item, not repeated). The first problem raises a validation error naming the line.
3. Refuse with 409 `keys_missing` when the change has live tasks and the text has no mark.
4. Find or create the change, and find, recover or create its milestone.
5. Upsert cards in text order, then items in text order. New cards get the first column, the active sprint (as `TasksController#create`) and the milestone, and go to the bottom of the column. Moved items get their new `parent_id`.
6. Archive linked tasks whose marks are gone, subtasks before their card.
7. Complete subtasks whose items are checked, then move cards whose items are all done to the done column.
8. Render the marked text, store it, stamp `imported_by` and `imported_at`.

`project.with_lock` serialises two imports of the same change, and board moves in the same project, so neither sees half of the other.

### 6. The parser mirrors OpenSpec's line rules

`OpenspecChange::TasksText` splits on `\n` (keeping `\r` with its line) and applies the rules of the spec requirement "Reading tasks.md". It uses OpenSpec's own task pattern, so a task line inside a code fence counts, as it does for `openspec archive`. It does not interpret any other Markdown.

Long titles are cut at the last space that leaves room for `…` within 255 characters, counted in characters, not bytes. The whole line then opens the description. Dogfooding this change showed why: 12 of its 18 items are longer than 255 characters, mostly because each one ends with how to verify it, and a plain cut left broken words and lost the verification. A space-free run longer than 254 characters is cut hard.

### 7. API and documentation

- `POST /api/projects/{project_id}/openspec_changes` (`importOpenspecChange`), with the body `{ name, artifacts: { tasks } }`. It answers 201 or 200 with `{ id, name, milestone, imported_by, imported_at, tasks, cards }`, and 409 `keys_missing` with `{ error, tasks }`.
- `GET /api/projects/{project_id}/openspec_changes/{name}` (`showOpenspecChange`), with the same shape.
- `TaskSerializer#card` gains `openspec_change: { id, name } | null`, so the board, sprint lists, the `assigned` view and task details all carry it.
- `importOpenspecChange`'s description explains the agent's loop in a few lines, because the MCP server shows it to agents as the tool's description:
  1. import and save the returned text into `tasks.md`;
  2. pick an assigned card and work through its items;
  3. complete each subtask, check its box and commit;
  4. move the card to the done column;
  5. import again.

The 409 envelope gains a `tasks` member, documented on this operation only.

### 8. Task keys on every task route

The six sub-route controllers switch from `find(params[:task_id])` to `find_by_ref!(params[:task_id])`, keeping their scopes (`kept`, subtasks only for completion). In `docs/openapi.yaml`, their `task_id` parameter takes the `id` parameter's schema from `showTask` (an integer or a key pattern), so the MCP tools accept `TEST-21`.

Without this, an agent that reads `<!-- goalner:TEST-21 -->` must call `showTask` first to learn that TEST-21's id is 23, and then call `completeSubtask` with 23. This came up while dogfooding.

Alternative: *put the id in the mark as well.* Rejected. Marks are read by people too, and keys are what people use.

### 9. Web client: the archive warning

The sprint archive dialog loads the sprint's tasks (`GET .../sprints/{id}/tasks`, already used by the sprints screen), groups the cards that have an `openspec_change` and are not in the done column by change name, and shows one warning line per change, in English and Russian. Archiving still works the same way.

## Risks / Trade-offs

- **The returned text is not written back** (the agent forgets or fails) → the next import without marks is refused with 409 and gets the marked text back. A text with only some marks is accepted, and the unmarked parts are created as new tasks, so duplicates are still possible if a client strips some marks. The tool description stresses saving the returned text.
- **`/opsx:update` or a person drops a mark** → the task is archived and a new one is created. History stays on the archived task, which is readable in the project archive.
- **Edits made in Goalner to linked titles and descriptions are overwritten by the next import** → the text is the source of truth for content. Discussion belongs in comments, which are never touched.
- **Carried-over cards lose their checklist and link** (spec requirement "Carried-over cards") → the archive dialog warns about it, and a later change decides how agents follow their cards across sprints.
- **Milestone progress double-counts carried-over cards** → existing behaviour for every task, left for that later change.
- **A large import holds the project lock** (up to 550 tasks) → it is bounded by the limits. A typical change has under 50 items.
- **Subtask order is creation order** → an item inserted in the middle of a section is listed last in Goalner. Its title keeps its OpenSpec number, so the order is still readable.

## Migration Plan

Two additive migrations: the `openspec_changes` table, and the nullable `tasks.openspec_change_id`. There is no backfill. Rolling back drops the column and the table, and the tasks created by imports stay as ordinary tasks.
