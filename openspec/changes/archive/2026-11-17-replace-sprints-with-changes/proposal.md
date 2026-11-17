# Proposal

## Why

Goalner is moving to agent-driven development: every piece of work is an OpenSpec change that agents explore, propose, build and archive. Sprints and milestones were made for people planning by the calendar, and for this they get in the way. A change today needs a sprint to show on the board and a milestone to show its progress, and only one sprint can be on the board at a time, although agents work on several changes side by side.

This change makes the change itself the unit of work. A project holds many open changes at once, each with its own board, and a change is archived with a button once it is done. Sprints and milestones go away. It is the first of three stages: the second gives each change an idea, a thread and a phase, and the third adds buttons that hand work to agents without a terminal. There is no production instance yet, so only the local development data needs to survive.

## What Changes

- **Changes replace sprints.** **BREAKING** A project holds changes. A change is named by its OpenSpec name (such as `add-labels`), unique among the project's open changes. Members create one by giving a name, and an import creates one too. A change has no dates, and no change is "active": all open changes are equal.
- **One record per change.** **BREAKING** A sprint and an OpenSpec change become one `Change`. The marked `tasks.md` text, and who imported it last and when, are kept on the change. A change is at most one OpenSpec change.
- **Milestones removed.** **BREAKING** Milestones, their screens, their API operations and MCP tools, and the milestone field of tasks are removed. A change shows its own progress.
- **Carry-over removed.** **BREAKING** Archiving no longer copies tasks anywhere, so copies, their link to the original task, and the "carried to" marker go.
- **A board per change.** The board shows one change at a time, picked from a row of tabs: one per open change, plus "Other tasks" for tasks in no change. Above the columns, a summary shows the change's name, how many cards are done, and an Archive action.
- **Backlog removed.** **BREAKING** The "Other tasks" tab replaces the backlog screen. The backlog task lists and sending a task to the backlog go.
- **Archive.** Archiving a change takes it and its tasks off the board. The tasks stay with the change. When cards are not done, the dialog warns and archiving stays possible. A new change may reuse an archived change's name.
- **Changes screen.** It replaces the sprints screen: each open change is a section listing its tasks, with a field that adds a task and a move menu (the other open changes and "Other tasks"), and archived changes are listed collapsed below.
- **Import into its change.** An import creates or updates the open change of that name, and its cards go into that change. Cards and subtasks an import created stay in their change. Tasks added to a change by hand are left alone by imports.
- **API and MCP.** Sprint operations become change operations (`listChanges`, `createChange`, `showChange`, `archiveChange`, `listChangeTasks`, `setTaskChange`). `activateSprint`, the five milestone operations and `showOpenspecChange` go; `showChange` returns what `showOpenspecChange` did. The MCP server follows `docs/openapi.yaml`, so its tools change with it.

Not included (stages 2 and 3):
- an idea text, a comment thread and a phase on a change;
- reading a change's proposal, design and specs in Goalner;
- Propose, Implement and Archive actions that start agents, and running `openspec archive` from Goalner;
- reopening an archived change.

## Capabilities

### New Capabilities

- `changes`: changes in a project. Covers:
  - what a change is and its name;
  - creating, listing and archiving changes;
  - putting tasks into a change, moving them between changes, and listing a change's tasks;
  - how tasks name their change.

### Modified Capabilities

- `openspec-changes`: an import creates or updates a change (spec `changes`) instead of an OpenSpec change linked to a milestone; its cards go into the change instead of the active sprint; cards an import created stay in their change; tasks added by hand are not archived by imports and do not trigger the missing-marks refusal; reading a change moves to `changes`; carried-over cards go.
- `project-board`: the board shows one change, or the tasks in no change; the backlog, done tasks outside sprints and the active-sprint rules are removed; deleting a column keeps each task's change.
- `projects`: the board snapshot is taken for one change or for no change, and lists the open changes.
- `tasks`: a task is created in a change instead of a sprint; the milestone field is removed; task details, archiving, assigned tasks and key routes name changes instead of sprints and milestones.
- `api-tokens`: changes are opened to tokens instead of sprints and milestones.
- `mcp-server`: the explicit-null example uses `setTaskChange`.
- `web-client`: board tabs and the change summary; the changes screen; the archive warning; the backlog, sprints and milestone screens removed; scenarios that used the backlog link use another section.
- `sprints`: every requirement removed, replaced by `changes`.
- `milestones`: every requirement removed.

## Impact

- Database: `changes` replaces `sprints` and `openspec_changes`; `milestones` is dropped; `tasks.change_id` replaces `sprint_id` and `openspec_change_id`, and `milestone_id` and `origin_task_id` are dropped. The migration turns each OpenSpec change into a change with its tasks. Sprints and milestones are dropped, so their other tasks end up in no change.
- Models: `Change` replaces `Sprint`, `Milestone` and `OpenspecChange`; the import and the tasks-text parser stay, working on `Change`.
- API: routes, controllers and serializers for changes, the board (`change_id`), tasks (`change_id`, no `milestone_id`, no backlog views), and the import.
- `docs/openapi.yaml`, and through it the MCP tool list. Running MCP servers must restart and clients reconnect to see the new tools.
- Web client: board tabs and summary, a changes screen in place of the sprints screen, the backlog and milestone screens removed, the task page's change picker, stores, router, navigation, English and Russian texts.
- Tests: models, requests, MCP tool list, frontend units and system tests that use sprints, milestones or the backlog.
- README: the agent workflow creates and archives changes instead of sprints.
