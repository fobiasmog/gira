# Design

## Context

See proposal.md for why. The current state that shapes the approach:

- **Change.** `changes` has `project_id`, `name` (unique among open changes), `archived_at`, `tasks_text`, `imported_by_id` and `imported_at`. `Change.task_counts_for` counts root, kept tasks per column for many changes in one query, and `ChangeSerializer.list` uses it for the changes list and for the board's `changes`. `Change.find_by_ref!` reads a path value as an id or an open change's name.
- **Done column.** The last column of a project is its done column (`Status`, `Board`).
- **Import.** `Change::Import` runs under the project's lock in one transaction, refuses any artifact but `tasks` (`ARTIFACTS = %w[tasks]`), and answers with `ChangeSerializer#detail`, which includes the marked text and every card.
- **Comments.** `comments.task_id` is required. `Api::Projects::Tasks::CommentsController` lists newest first and refuses a comment on an archived task with a validation error. `Api::CommentsController` finds the author's comment through `joins(:task)` and the projects the request reaches. `FilesController#visible?` lets a comment attachment through when the comment's task is in a reachable project. `CommentSerializer` has no task field.
- **Agents.** An agent is a `User` with an `agents` row; `User#agent?` tells them apart, and `UserSerializer#card` already marks agents.
- **Web client.** `CommentForm` and `CommentItem` take `post`, `save` and `remove` callbacks, so they work for any comment list. `MarkdownView` renders Markdown with the shared, restricted feature set. `ChangeTabs`, `ChangeSummary`, `ChangesPage` and `NewChangeDialog` exist from stage 1.
- **MCP.** Tools come from the operations of `docs/openapi.yaml`, and their results go into the agent's context in full.

## Goals / Non-Goals

**Goals:**
- Everything an agent and a person say about a change lives on the change, readable by both through the same API.
- Agents get small responses: nothing they just sent comes back, and files are read one at a time.
- `add-change-requests` can add requests without reshaping what this change adds.

**Non-Goals:**
- Requests and their buttons, and replacing "waiting for people" with request state (`add-change-requests`).
- Any notification about a waiting change.
- Editing OpenSpec files in Goalner, or showing diffs between imports.
- Rendering tables in Markdown: the source view covers them.

## Decisions

### 1. Idea and phase are columns of `changes`

- `idea` (text, nullable). `Change` validates at most 100,000 characters, like a task description, and refuses a change of `idea` unless the stored phase was `idea` before the update, and refuses any update of an archived change.
- `phase` (string, not null, default `idea`), with a check constraint allowing `idea`, `exploring`, `proposed` and `implementing`.

Alternatives:
- *A Postgres enum.* Adding a value later needs its own migration step, and a string with a check constraint is what the rest of the schema uses for small sets.
- *Store `done` as well.* See decision 2.

### 2. Done is derived, never stored

`Change#phase_reported` is `done` when the stored phase is `implementing`, the change has at least one kept root task, and all of them are in the project's last column; otherwise it is the stored phase. The API's `phase` field is this value. `Change.task_counts_for` already returns counts per column, so lists compute it from the counts they load, with one more lookup of each project's done column and no query per change.

A card reaches or leaves the done column through placement, completion, column deletion and reordering, imports, archiving and moving tasks between changes. Storing `done` would mean updating the change from every one of those paths. Deriving it keeps the rule in one method and cannot fall out of step.

Alternatives:
- *Callbacks on `Task` that update the change.* Covers the paths that go through `Task`, but column deletion and bulk updates bypass them, and the history would fill with Done/Implementing flips.

### 3. `updateChange` sets the idea and the phase

`PATCH /api/projects/{project_id}/changes/{change}` (`updateChange`) takes `idea` and `phase`, either or both. `phase` accepts the four stored values; `done` and anything else is a validation error on `phase`. It runs under the project's lock, like create and import, so a phase move and an import of the same change do not interleave. The response is the change as `showChange` returns it.

Alternatives:
- *A separate `PUT /changes/{change}/phase`.* One more tool for agents to find, and the idea and the phase are both plain fields of the change.

### 4. History in `change_events`

`change_events`: `change_id`, `actor_id` (users), `kind` (`phase` or `import`), `phase` (the phase moved to, for `phase`), `paths` (string array, the files of an import, `tasks.md` included), `created_at`. `Change#move_to!(phase, by:)` writes a `phase` event only when the phase actually changes. The import writes an `import` event, then moves the phase through the same method, so an import into a change in Exploring records both.

`showChange` returns `history` as `[{kind, actor, phase, paths, created_at}]`, oldest first. The client places these lines among the comments by time; the text of each line is built by the client in the viewer's language.

Alternatives:
- *Event rows in `comments`.* Comments are Markdown written by people, edited and deleted by their authors, and carry attachments; events have none of that, and storing English text would not follow the viewer's language.
- *A `listChangeHistory` operation.* History is short and the change page needs it at once, so it rides on `showChange`.

### 5. Files in `change_files`, read one at a time

`change_files`: `change_id`, `path` (`proposal.md`, `design.md` or `specs/<capability>/spec.md`), `text`, timestamps; unique on `[change_id, path]`. The import validates the artifacts (decision 6), then replaces the change's files in the same transaction: it upserts the paths it was sent and deletes the others. `tasks.md` stays in `changes.tasks_text`, because it carries the marks and the checkbox refresh.

`ChangeSerializer#detail` adds `files` as `[{path, length}]` in the order of the spec (proposal, design, specs by path). `GET /api/projects/{project_id}/changes/{change}/file?path=` (`showChangeFile`) returns `{path, text}`; a path that is not a file of the change is a 404. The web client loads a file when its tab is shown.

Alternatives:
- *Return every file's text in `showChange` and in the import's response.* An agent that imports four files would get all four back in its context on every import and every `showChange`.
- *A path segment instead of a query (`/files/specs/export/spec.md`).* Slashes in a path parameter need a glob route and escaping in the API document and in the MCP tool's URL template; a query parameter needs neither.

### 6. Import artifacts

`ARTIFACTS` becomes `tasks`, `proposal`, `design` and `specs`. `tasks` stays required, so the card logic does not change. `proposal` and `design` are strings of at most 100,000 characters. `specs` is an object of at most 50 entries whose keys match `\A[a-z0-9]+(?:-[a-z0-9]+)*(?:/[a-z0-9]+(?:-[a-z0-9]+)*)*\z` and whose values are strings of at most 100,000 characters; an invalid key is a validation error on `specs` that names the key. All of this is checked in `validate_input!`, before anything is written, so the import stays all or nothing.

After the cards, the import stores the files (decision 5), records the import event, and moves a change in `idea` or `exploring` to `proposed` (decision 4). A change the import creates is saved with `phase: proposed` directly.

The response stays `ChangeSerializer#detail`, which now carries file paths and lengths but no file text.

### 7. Thread: `comments.change_id`

`comments.change_id` (foreign key, nullable, indexed); `comments.task_id` becomes nullable; a check constraint `num_nonnulls(task_id, change_id) = 1`. `Comment` gets `belongs_to :change, optional: true`, `belongs_to :task, optional: true`, and `#project_id` from whichever it belongs to.

- `Api::Projects::Changes::CommentsController`: `index` (oldest first, any change of the project) and `create` (refused with a validation error on an archived change), opened to tokens. Operation ids `listChangeComments` and `createChangeComment`; `createChangeComment` takes a JSON body with `body` for MCP, and multipart with attachments for the web client, as `createComment` does.
- `Api::CommentsController#set_comment` finds the author's comment whose task or change is in a reachable project.
- `FilesController#visible?` uses `Comment#project_id`.
- `CommentSerializer` is unchanged; the list it is in says which task or change it belongs to.

Alternatives:
- *A polymorphic `commentable`.* No foreign keys, and every existing query on `task_id` would change. Two nullable foreign keys with a check keep the existing task paths untouched.
- *A separate `change_comments` table.* It would duplicate attachments, editing, deleting and file access.

### 8. Waiting for people

`Change.waiting_for_people(changes)` returns the ids of the given open changes whose newest kept comment was written by an agent: one query using `DISTINCT ON (change_id)` over kept comments ordered by `created_at DESC, id DESC`, joined to `agents` on the author. `ChangeSerializer.list` and `#detail` add `waiting_for_people`. The board's `changes` and the changes list get it for free through `ChangeSerializer.list`.

`add-change-requests` will replace this rule with request state; keeping it in one method makes that a local edit.

### 9. API summary

All paths are under `/api/projects/{project_id}`:

| Operation | Change |
|---|---|
| `POST /changes` (`createChange`) | also takes `idea` |
| `PATCH /changes/{change}` (`updateChange`) | new: `idea`, `phase` |
| `GET /changes`, `GET /board` | each change also has `phase` and `waiting_for_people` |
| `GET /changes/{change}` (`showChange`) | also `idea`, `phase`, `waiting_for_people`, `history`, `files` (paths and lengths) |
| `GET /changes/{change}/file?path=` (`showChangeFile`) | new |
| `GET`, `POST /changes/{change}/comments` (`listChangeComments`, `createChangeComment`) | new |
| `POST /openspec_changes` (`importOpenspecChange`) | accepts `proposal`, `design`, `specs`; moves the phase |

Token access: the new endpoints are opened with `allow_token_access`; writes need a read-write token as usual (spec `api-tokens`).

### 10. Web client

- **Route.** `/projects/:pid/changes/:ref` (`change`), where `ref` is the name of an open change or the id of any change, read like a task key. `ChangesPage` stays at `/projects/:pid/changes`.
- **`ChangePage`.** Loads `showChange`. Header: name, a stepper of the five phases (current and passed marked in text), card counts with a link to the board tab, a phase `<select>` (Idea, Exploring, Proposed, Implementing) and the existing `ArchiveChangeDialog`. Left column: the idea through `MarkdownView` with an edit form while the phase is `idea`; the thread, merging `listChangeComments` and `history` by time, reusing `CommentItem` and `CommentForm` with change callbacks. Right column: file tabs (`files` paths plus `tasks.md`), loading `showChangeFile` per tab, shown through `MarkdownView` or, with the source switch, in a `<pre>`; the last importer and time.
- **Archived change.** Opened by id; the page hides the phase menu, idea editing, the comment form and Archive. `ChangesPage` links archived changes by id, open ones by name.
- **Board.** `ChangeTabs` shows the phase and a waiting marker (a dot with a visually hidden "Waiting for you") from the board's `changes`. `ChangeSummary` links the name to the change page and shows the phase.
- **Changes screen.** Section headers show the phase and the waiting marker, and the name links to the change page.
- **New change dialog.** A Markdown `<textarea>` for the idea, sent as `idea`.
- **Texts.** English and Russian for phases, history lines, the waiting marker, the source switch and the page's labels.

### 11. Data migration

One migration on the development database: add `idea` and `phase`; set `phase` to `implementing` for changes with `tasks_text`, so their history of work is reflected (`add-openspec-changes`, for one), and leave the rest in `idea`; create `change_files` and `change_events`; add `comments.change_id`, make `task_id` nullable and add the check constraint. No history is invented for existing changes. The migration is reversible as long as no comment belongs to a change.

## Risks / Trade-offs

- [An agent posts a status update, and the change shows as waiting for people although nothing is asked] → Agents are told in the README to post in the thread only to ask or to report a finished step. `add-change-requests` replaces the rule with request state.
- [Anyone can move any change to any phase] → Intended as the override the user asked for. The history records who moved it.
- [Tables and other Markdown outside the shared set lose their structure when shown formatted] → The source switch shows the file as imported.
- [A change's files describe the last import, not what is committed] → The page shows who imported last and when. The repository stays the source, as for `tasks.md`.
- [Large responses through MCP] → File texts are only returned by `showChangeFile`; `showChange` and the import return paths and lengths.
- [Running MCP servers and clients keep the old tools] → Restart the MCP server and reconnect (`/mcp`), as after stage 1. Tools that keep their name may keep their old schema in a Claude Code session until it reconnects.

## Migration Plan

1. Deploy the code and run the migration.
2. Restart the MCP server and reconnect MCP clients so they see `updateChange`, `listChangeComments`, `createChangeComment` and `showChangeFile`, and the new fields of the existing tools.
3. Rollback: run the migration down while no comment belongs to a change, and check out the previous commit.
