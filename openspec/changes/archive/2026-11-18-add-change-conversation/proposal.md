# Proposal

## Why

Stage 1 made the change the unit of work, but everything said about a change still happens in a terminal: the idea, the agent's questions, your answers and the review of its proposal. Goalner only sees `tasks.md`. This is the first half of stage 2: the change itself holds the conversation, so the person steering it can do so from Goalner. The second half, `add-change-requests`, adds buttons that hand the next step to a waiting agent, and builds on what this change adds.

## What Changes

- **Idea.** A change gets an idea: Markdown that says what the work is, given when the change is created. It can be edited while the change is in Idea and is fixed once exploring starts, so later corrections go in the thread where the agent sees them as new input.
- **Phase.** A change has a phase: Idea, Exploring, Proposed, Implementing or Done. A new change starts in Idea. Agents move it through MCP, and members can move it to any phase but Done from a phase menu. Goalner reports Done by itself while every card of a change in Implementing is in the done column. An import moves a change in Idea or Exploring to Proposed, and a change that an import creates starts in Proposed.
- **History.** Every phase move and every import is recorded with who did it and when, and shown among the thread's comments.
- **Thread.** A change gets a thread of comments, with the same Markdown and attachment rules as task comments, listed oldest first. Agents ask their questions there and people answer there.
- **Waiting for people.** A change whose newest comment was written by an agent is waiting for people. The board tabs and the changes screen mark it.
- **All OpenSpec files.** An import accepts `proposal`, `design` and the delta `specs` as well as `tasks`, and stores them as sent. A change's files are those of its last import. Opening a change lists their paths, and a separate request reads one file, so that agents do not get every file back in their context.
- **Change page.** Each change gets a page with its phases, phase menu, idea, thread with history, and its files shown formatted or as source. The board summary and the changes screen link to it.
- **New change dialog.** It asks for the idea as well as the name.
- **API and MCP.** `createChange` takes `idea`; `showChange` and the change lists return `idea`, `phase`, `waiting_for_people`, `history` and file paths. New operations: `updateChange` (idea, phase), `listChangeComments`, `createChangeComment` and `showChangeFile`. `importOpenspecChange` accepts the new artifacts.

Not included:
- requests, and the Start exploring, Implement and Archive buttons that create them (`add-change-requests`);
- running agents anywhere but the user's own machine, and pushing or merging from Goalner (stage 3);
- editing OpenSpec files in Goalner, and email about a waiting change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `changes`: a change's idea, phase and history; whether it is waiting for people; creating a change with an idea; lists and opening a change return the new fields and the paths of its files.
- `openspec-changes`: an import accepts the proposal, the design and the delta specs, stores them as the change's files, and moves the change to Proposed; reading one file of a change; limits for the new files.
- `comments`: a thread of comments on each change; editing and deleting them as task comments.
- `api-tokens`: the change thread and the change files are open to tokens.
- `markdown-content`: change ideas, change threads and change files are shown through the same renderer.
- `web-client`: the change page; the phase and the waiting marker on the board tabs, the board summary and the changes screen; the idea field of the new change dialog.

## Impact

- Database: `changes.idea` and `changes.phase`; new tables `change_files` and `change_events`; `comments.change_id`, with `comments.task_id` made optional and a check that a comment belongs to exactly one task or change.
- Models: `Change` (idea, phase, the derived Done, waiting for people), `ChangeFile`, `ChangeEvent`, `Comment`; `Change::Import` takes the new artifacts, stores files and moves the phase.
- API: `ChangesController#update`, change comments and change file controllers, `ChangeSerializer`, the comment edit and delete lookup, and file downloads for attachments of change comments.
- `docs/openapi.yaml`, and through it the MCP tools. The MCP server needs a restart and clients a reconnect.
- Web client: a change page with its route, the board tabs and summary, the changes screen, the new change dialog, comment components shared with the task page, English and Russian texts.
- README: the agent workflow goes through the thread and imports every file of a change.
