# Proposal

## Why

Goalner is meant to steer AI agents that build software, and the work they do is planned with OpenSpec: each change ends in a `tasks.md` checklist. Today that checklist lives only in git, so nobody sees in Goalner what agents are about to do or how far they got, and agents cannot be handed parts of a change as tasks.

This change lets an agent (or a person) push an OpenSpec change into a project: its sections become cards on the board, its items become their subtasks, and progress shows on a milestone. It is the first step toward steering everything from Goalner, where worker agents in VMs read the repository, plan, implement, test and push on their own; those workers will report through the same import.

## What Changes

- **OpenSpec changes in a project.** A project gains OpenSpec changes, each identified by its OpenSpec name (such as `add-agents`) and linked to a milestone of the same name.
- **Import.** One request creates or updates a change from the raw text of its `tasks.md`:
  - each `##` section becomes a card, titled `<change>: <section>`;
  - each checkbox item becomes a subtask of its section's card; extra lines and nested items go into the subtask's description;
  - items before the first section go on a card `<change>: Tasks`;
  - the cards carry the change's milestone. New cards join the active sprint when there is one, and stay outside sprints otherwise.
- **Goalner keys in `tasks.md`.** The import answers with the same text, with each section and item marked with its Goalner key (`<!-- goalner:TEST-15 -->`). The client saves that text into the repository. Later imports recognise sections and items by these keys, so renumbering, rewording and reordering keep each task's history, assignee and comments.
- **Re-import.** Importing the same change again:
  - creates cards and subtasks for new, unmarked sections and items;
  - updates the titles and descriptions of marked ones, and moves an item to another card when it moved to another section;
  - archives the tasks whose marks are gone from the text;
  - marks as done every item checked in the text, and checks in the returned text every item done in Goalner. Nothing is ever reopened by an import;
  - is refused when the text carries no marks at all although the change already has tasks, so that a lost write-back cannot duplicate the change.
- **Long items.** OpenSpec items often run past 255 characters. Their titles are cut at a word boundary and end with `…`, and the whole line opens the subtask's description.
- **API and MCP.** The import and the reading of a change are opened to tokens with read-write and read-only access respectively, so agents use them through the API and, without any change to the MCP server, as MCP tools. Task responses name the OpenSpec change a task belongs to.
- **Task keys everywhere.** Every task request that names a task in its path (placement, sprint, label, subtasks, completion, comments) accepts its key as well as its id, so an agent can act on the key it reads in a mark (`TEST-21`) without looking up the id first.
- **Web client.** Archiving a sprint warns when it holds unfinished cards of an OpenSpec change. No new screen: the board and milestones show the work.

Not included:
- carrying OpenSpec cards over to another sprint properly. Carry-over copies a card without its subtasks and without its link to the change, as for any task; the original card keeps both. How working agents should react to a sprint being archived is a later change;
- counting carried-over tasks once in milestone progress;
- importing the proposal, design or specs of a change, a state for changes (requested, proposed, approved and so on), approving a change, and creating a change from Goalner;
- linking a project to a git repository, and anything that reads or writes git;
- worker agents in VMs, dispatching work to agents, and claiming tasks atomically;
- the order in which sections may be worked on.

## Capabilities

### New Capabilities

- `openspec-changes`: OpenSpec changes in a project. Covers:
  - what a change is, its name and its milestone;
  - how `tasks.md` is read into cards and subtasks;
  - Goalner keys in the tasks text, and what a re-import does with them;
  - reading a change, limits, and how tasks name their change.

### Modified Capabilities

- `api-tokens`: the import and the reading of OpenSpec changes are opened to tokens.
- `web-client`: archiving a sprint warns about unfinished OpenSpec cards in it.
- `tasks`: every task request accepts the task's key as well as its id.

## Impact

- Database: an `openspec_changes` table, and an `openspec_change_id` reference on `tasks`.
- API: `POST /api/projects/{project_id}/openspec_changes` and `GET /api/projects/{project_id}/openspec_changes/{name}`; task cards and details gain `openspec_change`.
- Task sub-route controllers (placement, sprint, label, subtasks, completion, comments): look tasks up by id or key.
- `docs/openapi.yaml`: two operations, which the MCP server turns into the tools `importOpenspecChange` and `showOpenspecChange`, and `task_id` typed as an id or a key on the task sub-routes.
- Depends on the MCP server returning UTF-8 responses intact (a separate fix, now made): before it, a successful call whose response held non-ASCII text, such as `…` or Russian, was reported as an internal error.
- Web client: the sprint archive dialog.
- README: how agents work through an OpenSpec change with Goalner.
