## ADDED Requirements

### Requirement: Cards and subtasks in their change
Each section SHALL become a root task, called a card here, titled `<change name>: <section title>`. Its description SHALL start with a line naming the change folder `openspec/changes/<change name>/` and the section, followed by the section's introduction. Each item SHALL become a subtask of its section's card, with the item's title and description. Every card and subtask that an import creates SHALL belong to the change (spec `changes`), whichever change or board anyone has open. A new card SHALL start in the first column, and SHALL be added at the bottom of its column in the order of the text. A card SHALL be moved to the done column when every one of its items is done and it is not there yet.

#### Scenario: Cards in their change
- **WHEN** `add-labels` is imported for the first time while a member has the board of `export-csv` open
- **THEN** its cards belong to `add-labels` and are shown on the board of `add-labels`, and the board of `export-csv` does not show them

#### Scenario: Change progress
- **WHEN** `add-labels` is imported with two sections of three items each, and every item of the first section is checked
- **THEN** the first card is in the done column, `add-labels` is listed with 1 card in the done column out of 2, and the second card shows 0 of 3 subtasks done

## MODIFIED Requirements

### Requirement: Import a change
A member of a non-archived project SHALL be able to import an OpenSpec change by sending its name and, under `artifacts`, the text of its `tasks.md` as `tasks`. The import SHALL work on the project's open change of that name (spec `changes`). When the project has no open change of that name, the import SHALL create it and SHALL respond with HTTP 201; otherwise it SHALL respond with HTTP 200. The first import into a change SHALL create its cards and their subtasks, and a later import SHALL update them (requirement "Import again"). An import SHALL succeed or fail as a whole: when any part of it is refused, nothing SHALL change. The response SHALL contain the change, its marked text (requirement "Goalner keys in the tasks text") and its cards. Any artifact other than `tasks` SHALL be refused with a validation error. The name SHALL follow the rules for change names (spec `changes`), and an invalid name SHALL be refused with a validation error. The importer SHALL be recorded as the creator of the tasks the import creates, and as the change's last importer, with the time of the import. An import SHALL NOT assign tasks to anyone and SHALL NOT send any notification.

#### Scenario: First import
- **WHEN** a member imports `add-labels` into TEST, which has no open change of that name, with a `tasks` text holding two sections of three items each
- **THEN** the response is HTTP 201, TEST holds the open change `add-labels`, and it has two new cards with three subtasks each, created by the member and assigned to nobody

#### Scenario: Change created by hand
- **WHEN** a member created the change `export-csv` on the changes screen, added the task TEST-31 to it by hand, and an agent then imports `export-csv` for the first time
- **THEN** the response is HTTP 200, the cards and subtasks are created in `export-csv`, and TEST-31 is left as it is

#### Scenario: Import again
- **WHEN** a member imports `add-labels` a second time with the marked text returned by the first import
- **THEN** the response is HTTP 200 and no task is created

#### Scenario: Invalid name
- **WHEN** a member imports a change named `Add Labels`
- **THEN** the response is HTTP 422 with a validation error on the name, and nothing is created

#### Scenario: All or nothing
- **WHEN** a member imports a text in which one item carries the mark of a task of another change
- **THEN** the response is HTTP 422, and no change or task is created or changed

#### Scenario: Import after archiving
- **WHEN** `add-labels` was archived and a member imports `add-labels` with the marked text it last returned
- **THEN** the response is HTTP 422 with a validation error naming the first marked line, because the marks name tasks of the archived change, and no change is created

#### Scenario: Other artifacts
- **WHEN** a member imports `add-labels` with artifacts `tasks` and `proposal`
- **THEN** the response is HTTP 422 with a validation error on `proposal`, and nothing changes

#### Scenario: Archived project
- **WHEN** a member imports a change into an archived project
- **THEN** the response is HTTP 404 and nothing is created

#### Scenario: Agent through MCP
- **WHEN** a client holding agent Fish's read-write MCP token calls the import tool for TEST
- **THEN** the cards and subtasks are created in TEST with Fish as their creator

### Requirement: Goalner keys in the tasks text
The response to an import SHALL contain the imported text with the first line of each section heading and of each item ending in one space and the mark `<!-- goalner:<key> -->`, where `<key>` is the key of its card or subtask. Apart from these marks and the checkboxes (requirement "Import again"), the returned text SHALL be the text as sent. A mark already in the text SHALL be replaced by the current one. A mark SHALL identify a task by the number after its last hyphen, within the change's project, whatever the letters before it. The import SHALL be refused with a validation error that names the line when a mark:
- names a task that does not exist in the project or does not belong to the change;
- names a card on an item's line, or a subtask on a heading;
- appears on more than one line.

A mark naming an archived task of the change SHALL be treated as no mark: a new task SHALL be created and the mark replaced. A mark naming a task that was added to the change by hand SHALL be accepted, and that task SHALL from then on be updated by imports like any other marked task.

#### Scenario: Marks returned
- **WHEN** `add-labels` is imported for the first time and its card "1. Model" becomes TEST-20 and the item 1.1 becomes TEST-21
- **THEN** the returned text holds the lines `## 1. Model <!-- goalner:TEST-20 -->` and `- [ ] 1.1 Add the table <!-- goalner:TEST-21 -->`

#### Scenario: Short name changed
- **WHEN** the owner changes TEST's short name to QA and the text marked `goalner:TEST-21` is imported again
- **THEN** the mark is recognised as task 21, and the returned text holds `goalner:QA-21`

#### Scenario: Mark of another change
- **WHEN** an item of `add-labels` carries the mark of a subtask of `add-agents`
- **THEN** the response is HTTP 422 naming that line, and nothing changes

#### Scenario: Mark used twice
- **WHEN** two items carry the mark `goalner:TEST-21`
- **THEN** the response is HTTP 422 naming the second line, and nothing changes

#### Scenario: Adopting a task added by hand
- **WHEN** TEST-30 was created by hand on the board of `add-labels`, and a section of the text of `add-labels` carries the mark `goalner:TEST-30`
- **THEN** TEST-30 becomes that section's card, takes its title and description, and is marked in the returned text

### Requirement: Import again
When a change is imported again, its sections and items SHALL be matched to its tasks by their marks:
- a marked section or item SHALL update its task's title and description, so the text wins over edits made in Goalner. A marked item under another section than before SHALL become a subtask of that section's card. A task's column, position, assignee and comments SHALL stay as they are;
- a section or item without a mark SHALL get a new card or subtask;
- each task whose mark was in the change's previous marked text and is no longer in the text SHALL be archived, a card together with its remaining subtasks. Tasks of the change that were never marked SHALL be left as they are;
- each checked item SHALL be done. In the returned text, the checkbox of each item whose subtask is done SHALL be checked. An import SHALL NOT reopen any task.

An import SHALL be refused with HTTP 409 and the code `keys_missing` when the change's previous marked text marks tasks that are not archived and the text carries no mark at all. The response SHALL then contain the change's marked text as opening the change returns it (requirement "Read a change"), and nothing SHALL change.

#### Scenario: Renumbered item
- **WHEN** an item marked `goalner:TEST-21` and assigned to agent Fish is renumbered from "1.1" to "1.2" in the text
- **THEN** TEST-21 is titled "1.2 Add the table" and is still assigned to Fish, with its comments

#### Scenario: Title edited in Goalner
- **WHEN** a member renames TEST-21 in Goalner and the change is imported again with TEST-21's mark
- **THEN** TEST-21 has the title from the text

#### Scenario: Item moved to another section
- **WHEN** the item marked `goalner:TEST-21` now stands under the section marked `goalner:TEST-25`
- **THEN** TEST-21 is a subtask of TEST-25

#### Scenario: Item removed
- **WHEN** the item marked `goalner:TEST-22` is no longer in the text
- **THEN** TEST-22 is archived

#### Scenario: Section removed
- **WHEN** the section marked `goalner:TEST-20` and its items are no longer in the text
- **THEN** TEST-20 and its subtasks are archived

#### Scenario: Task added by hand
- **WHEN** a member created TEST-30 on the board of `add-labels`, and `add-labels` is imported again with a text that does not mention it
- **THEN** TEST-30 is not archived and is unchanged

#### Scenario: Checked in the text
- **WHEN** the item marked `goalner:TEST-22` is checked in the text and TEST-22 is not done
- **THEN** TEST-22 is done

#### Scenario: Done in Goalner
- **WHEN** agent Fish completed TEST-22 in Goalner and the text still shows its box unchecked
- **THEN** TEST-22 stays done, and the returned text shows its box checked

#### Scenario: Lost write-back
- **WHEN** the last marked text of `add-labels` marks tasks that are not archived, and `add-labels` is imported again with a text that carries no mark
- **THEN** the response is HTTP 409 with the code `keys_missing` and the marked text as last returned, and no task is created

### Requirement: Read a change
Opening a change (spec `changes`) SHALL also return who imported it last and when, and its marked text as last returned, with the checkbox of every item whose subtask is done now checked. For a change that was never imported, these SHALL be `null`.

#### Scenario: Read
- **WHEN** a read-only token for TEST opens `add-labels` after Fish completed TEST-22
- **THEN** the response contains the marked text with TEST-22's box checked, and the cards of `add-labels`

#### Scenario: Never imported
- **WHEN** a member opens `export-csv`, which was created on the changes screen and never imported
- **THEN** its last importer, import time and marked text are `null`

#### Scenario: Unknown change
- **WHEN** a member opens the change `no-such-change`
- **THEN** the response is HTTP 404

### Requirement: Limits of a change
The `tasks` text SHALL be at most 100,000 characters long, and SHALL hold at most 50 sections and 500 items. An import that would exceed a limit SHALL be refused with a validation error and SHALL change nothing.

#### Scenario: Too many items
- **WHEN** a member imports a text with 501 items
- **THEN** the response is HTTP 422 and nothing is created

## REMOVED Requirements

### Requirement: Cards and subtasks of a change
**Reason**: Cards no longer join the active sprint or carry a milestone. Replaced by "Cards and subtasks in their change", where cards belong to their change.
**Migration**: See requirement "Cards and subtasks in their change".

### Requirement: OpenSpec changes in a project
**Reason**: An OpenSpec change is now a change of the project (spec `changes`). It has no milestone, and its name is unique among the project's open changes instead of among all of them.
**Migration**: See "Changes in a project" in spec `changes`. Existing OpenSpec changes become changes with the same name and tasks; their milestones are dropped.

### Requirement: Tasks name their change
**Reason**: The change a task belongs to is defined in spec `changes`, which covers every change, imported or not.
**Migration**: See "Tasks name their change" in spec `changes`. Task responses name their change under `change` instead of `openspec_change`.

### Requirement: Carried-over cards
**Reason**: Carry-over is removed with sprints. A card stays in its change until the change is archived.
**Migration**: None. Unfinished cards stay with their change when it is archived.
