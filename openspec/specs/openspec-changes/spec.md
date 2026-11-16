# openspec-changes Specification

## Purpose

Lets agents and people push an OpenSpec change into a project, so that its `tasks.md` checklist becomes cards and subtasks on the board, its progress shows on a milestone, and the checklist and the tasks stay in step across later imports.

## Requirements

### Requirement: OpenSpec changes in a project
A project SHALL hold OpenSpec changes. Each change SHALL have a name of 1 to 100 characters made of groups of lowercase Latin letters and digits joined by single hyphens, unique within the project. Each change SHALL be linked to a milestone of the project titled with the change's name, and SHALL record who imported it last and when. Every card and subtask that an import creates SHALL belong to the change.

#### Scenario: Valid name
- **WHEN** a member imports a change named `add-agents` into TEST
- **THEN** TEST holds the change `add-agents`, linked to a new milestone titled "add-agents"

#### Scenario: Invalid name
- **WHEN** a member imports a change named `Add Agents`
- **THEN** the response is HTTP 422 with a validation error on the name, and nothing is created

#### Scenario: Same name in two projects
- **WHEN** TEST already holds the change `add-agents` and a member imports a change named `add-agents` into GOAL
- **THEN** GOAL gets a change of its own, with its own milestone, and TEST's change is unchanged

#### Scenario: Deleted milestone
- **WHEN** a member deleted the milestone of `add-agents` and the change is imported again
- **THEN** the milestone is recovered, and the change's cards still carry it

### Requirement: Import a change
A member of a non-archived project SHALL be able to import an OpenSpec change by sending its name and, under `artifacts`, the text of its `tasks.md` as `tasks`. The first import of a name SHALL create the change, its milestone, its cards and their subtasks, and SHALL respond with HTTP 201. A later import of the same name SHALL update them (requirement "Import again") and SHALL respond with HTTP 200. An import SHALL succeed or fail as a whole: when any part of it is refused, nothing SHALL change. The response SHALL contain the change, its marked text (requirement "Goalner keys in the tasks text") and its cards. Any artifact other than `tasks` SHALL be refused with a validation error. The importer SHALL be recorded as the creator of the tasks the import creates. An import SHALL NOT assign tasks to anyone and SHALL NOT send any notification.

#### Scenario: First import
- **WHEN** a member imports `add-labels` with a `tasks` text holding two sections of three items each
- **THEN** the response is HTTP 201, and TEST has two new cards with three subtasks each, created by the member and assigned to nobody

#### Scenario: Import again
- **WHEN** a member imports `add-labels` a second time with the marked text returned by the first import
- **THEN** the response is HTTP 200 and no task is created

#### Scenario: All or nothing
- **WHEN** a member imports a text in which one item carries the mark of a task of another change
- **THEN** the response is HTTP 422, and no change, milestone or task is created or changed

#### Scenario: Other artifacts
- **WHEN** a member imports `add-labels` with artifacts `tasks` and `proposal`
- **THEN** the response is HTTP 422 with a validation error on `proposal`, and nothing changes

#### Scenario: Archived project
- **WHEN** a member imports a change into an archived project
- **THEN** the response is HTTP 404 and nothing is created

#### Scenario: Agent through MCP
- **WHEN** a client holding agent Fish's read-write MCP token calls the import tool for TEST
- **THEN** the cards and subtasks are created in TEST with Fish as their creator

### Requirement: Reading tasks.md
The import SHALL read the `tasks` text line by line:
- a level-2 heading (`## `) SHALL start a section, titled with the heading's text;
- a task line SHALL be a line that OpenSpec counts as a task: optional leading whitespace, a `-` or `*` bullet, then a checkbox `[ ]`, `[x]` or `[X]`. The first task line of a section SHALL set the section's item indentation. A task line indented no deeper than that SHALL start an item, titled with the text after its checkbox and checked when its box holds `x` or `X`;
- every other line after an item, a deeper task line included, SHALL belong to that item's description until the next item or section, with the indentation common to its lines removed and with blank lines at its start and end dropped;
- the lines between a section's heading and its first item SHALL be the section's introduction, read the same way;
- only a mark at the very end of a heading or item line SHALL count as a mark, and it SHALL NOT be part of the title;
- items before the first section SHALL belong to a section titled "Tasks";
- a section without items SHALL produce no card, and lines before the first section or item SHALL be ignored.

A title longer than 255 characters SHALL be cut at the last space that leaves room for the ellipsis `…` within 255 characters, and SHALL end with `…`. The whole uncut line SHALL then start the task's description, followed by the rest of the description. Titles and descriptions SHALL keep any UTF-8 text as sent.

#### Scenario: Long item
- **WHEN** an item's line holds 310 characters, and the line is followed by the line `  - a detail.`
- **THEN** its subtask's title is cut at a word boundary, ends with `…` and is at most 255 characters long, and its description is the whole line followed by `- a detail.`

#### Scenario: Sections and items
- **WHEN** `add-labels` is imported with the text `## 1. Model`, `- [x] 1.1 Add the table`, `- [ ] 1.2 Add the model`
- **THEN** the card "add-labels: 1. Model" has the subtasks "1.1 Add the table", which is done, and "1.2 Add the model", which is not

#### Scenario: Item over several lines
- **WHEN** an item `- [ ] 2.3 Add the handle:` is followed by the lines `  - word lists;` and `  - retries.`
- **THEN** its subtask is titled "2.3 Add the handle:" and its description is `- word lists;` and `- retries.` on two lines

#### Scenario: Nested task line
- **WHEN** the item `- [ ] 1.1 Prepare` is followed by `  - [ ] 1.1.1 Check the schema`
- **THEN** the section has one item, "1.1 Prepare", whose description is `- [ ] 1.1.1 Check the schema`

#### Scenario: Other bullet and checkbox forms
- **WHEN** a section holds the lines `* [X] 3.1 Done item` and `- [ ] 3.2 Open item`
- **THEN** both are items, and only "3.1 Done item" is done

#### Scenario: Items before the first section
- **WHEN** the text starts with `# Tasks` followed by `- [ ] Write the docs`, before any `##` heading
- **THEN** the card "<change>: Tasks" has the subtask "Write the docs", and the line `# Tasks` is ignored

#### Scenario: Section without items
- **WHEN** the text holds `## Notes` followed only by a paragraph
- **THEN** no card is created for it

### Requirement: Cards and subtasks of a change
Each section SHALL become a root task, called a card here, titled `<change name>: <section title>`. Its description SHALL start with a line naming the change folder `openspec/changes/<change name>/` and the section, followed by the section's introduction. Each item SHALL become a subtask of its section's card, with the item's title and description. Cards SHALL carry the change's milestone; subtasks SHALL NOT, so the milestone's progress counts sections. A new card SHALL join the project's active sprint when one exists and SHALL stay outside sprints otherwise. It SHALL start in the first column, and SHALL be added at the bottom of its column in the order of the text. A card SHALL be moved to the done column when every one of its items is done and it is not there yet.

#### Scenario: Active sprint
- **WHEN** `add-labels` is imported for the first time while the sprint "Openspec integration" is active
- **THEN** its cards are in "Openspec integration" and shown on the board

#### Scenario: No active sprint
- **WHEN** `add-labels` is imported for the first time while no sprint is active
- **THEN** its cards are in no sprint and shown on the board

#### Scenario: Milestone progress
- **WHEN** `add-labels` is imported with two sections of three items each, and every item of the first section is checked
- **THEN** the milestone "add-labels" shows 1 of 2 done, the first card is in the done column, and the second card shows 0 of 3 subtasks done

### Requirement: Goalner keys in the tasks text
The response to an import SHALL contain the imported text with the first line of each section heading and of each item ending in one space and the mark `<!-- goalner:<key> -->`, where `<key>` is the key of its card or subtask. Apart from these marks and the checkboxes (requirement "Import again"), the returned text SHALL be the text as sent. A mark already in the text SHALL be replaced by the current one. A mark SHALL identify a task by the number after its last hyphen, within the change's project, whatever the letters before it. The import SHALL be refused with a validation error that names the line when a mark:
- names a task that does not exist in the project or does not belong to the change;
- names a card on an item's line, or a subtask on a heading;
- appears on more than one line.

A mark naming an archived task of the change SHALL be treated as no mark: a new task SHALL be created and the mark replaced.

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

### Requirement: Import again
When a change is imported again, its sections and items SHALL be matched to its tasks by their marks:
- a marked section or item SHALL update its task's title and description, so the text wins over edits made in Goalner. A marked item under another section than before SHALL become a subtask of that section's card. A task's column, sprint, position, assignee and comments SHALL stay as they are;
- a section or item without a mark SHALL get a new card or subtask;
- each task of the change whose mark is no longer in the text SHALL be archived, a card together with its remaining subtasks;
- each checked item SHALL be done. In the returned text, the checkbox of each item whose subtask is done SHALL be checked. An import SHALL NOT reopen any task.

An import SHALL be refused with HTTP 409 and the code `keys_missing` when the change has tasks that are not archived and the text carries no mark at all. The response SHALL then contain the change's marked text as opening the change returns it (requirement "Read a change"), and nothing SHALL change.

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

#### Scenario: Checked in the text
- **WHEN** the item marked `goalner:TEST-22` is checked in the text and TEST-22 is not done
- **THEN** TEST-22 is done

#### Scenario: Done in Goalner
- **WHEN** agent Fish completed TEST-22 in Goalner and the text still shows its box unchecked
- **THEN** TEST-22 stays done, and the returned text shows its box checked

#### Scenario: Lost write-back
- **WHEN** `add-labels` has tasks and is imported again with a text that carries no mark
- **THEN** the response is HTTP 409 with the code `keys_missing` and the marked text as last returned, and no task is created

### Requirement: Read a change
A member SHALL be able to open a change of their project by its name. The response SHALL contain its name, its milestone, who imported it last and when, its marked text as last returned with the checkbox of every item whose subtask is done now checked, and its cards that are not archived, each with its subtask counts. An unknown name SHALL receive HTTP 404.

#### Scenario: Read
- **WHEN** a read-only token for TEST opens `add-labels` after Fish completed TEST-22
- **THEN** the response contains the marked text with TEST-22's box checked, and the cards of `add-labels`

#### Scenario: Unknown change
- **WHEN** a member opens the change `no-such-change`
- **THEN** the response is HTTP 404

### Requirement: Limits of a change
The `tasks` text SHALL be at most 100,000 characters long, and a change SHALL have at most 50 cards and 500 subtasks that are not archived. An import that would exceed a limit SHALL be refused with a validation error and SHALL change nothing.

#### Scenario: Too many items
- **WHEN** a member imports a text with 501 items
- **THEN** the response is HTTP 422 and nothing is created

### Requirement: Tasks name their change
Tasks in lists and in task details SHALL include the OpenSpec change they belong to, with its id and name, or `null` for a task that belongs to none.

#### Scenario: Card of a change
- **WHEN** a member opens TEST-20, a card of `add-labels`
- **THEN** the response names the change `add-labels`

#### Scenario: Ordinary task
- **WHEN** a member opens a task created on the board
- **THEN** its OpenSpec change is `null`

### Requirement: Carried-over cards
Carrying a sprint's tasks over (spec `sprints`) SHALL treat cards of a change as any task: the copy SHALL belong to no change and SHALL have no subtasks, while the original keeps its link to the change and its subtasks, and later imports keep updating the original.

#### Scenario: Card carried over
- **WHEN** the sprint holding the unfinished card TEST-20 is archived with its tasks carried over to "Sprint 5", and `add-labels` is imported again
- **THEN** the copy of TEST-20 in "Sprint 5" belongs to no change, and the import updates TEST-20
