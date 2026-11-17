## ADDED Requirements

### Requirement: Requests on the change page
On the page of an open change (requirement "Change page"), the client SHALL show:
- when the change has no open request (spec `change-requests`), a button that asks for the step that fits its phase: "Start exploring" in Idea, "Write the proposal" in Exploring, "Implement" in Proposed, "Continue implementing" in Implementing, and "Archive and sync specs" in Done. Text in the comment field SHALL go with the request as its comment, and the field SHALL then be emptied;
- when the change has an open request, its step and its state in words (waiting for an agent, or taken by whom and since when), and a "Cancel request" action. When that request is a reply request that is waiting, the button for the phase's step SHALL be shown as well;
- beside the comment field, while a comment would create a reply request, a note that posting asks an agent to reply.

In the thread, each request asked for, taken, finished or cancelled SHALL appear as a history line naming who did it and which step. The page of an archived change SHALL offer no request actions.

#### Scenario: Start exploring
- **WHEN** a member opens the page of `export-csv`, which is in Idea with no open request, and chooses "Start exploring"
- **THEN** the page shows an explore request waiting for an agent, with "Cancel request", and no "Start exploring" button

#### Scenario: Button for the phase
- **WHEN** a member opens the page of `export-csv`, which is in Proposed with no open request
- **THEN** the page offers "Implement"

#### Scenario: Comment with the step
- **WHEN** a member types "Start with the API." into the comment field of `export-csv` and chooses "Implement"
- **THEN** the comment is shown in the thread, the field is empty, and the page shows an implement request waiting for an agent

#### Scenario: Taken request
- **WHEN** agent Fish took the implement request of `export-csv` at 14:05
- **THEN** the page says that Fish has taken it since 14:05, and offers "Cancel request"

#### Scenario: Cancel
- **WHEN** a member chooses "Cancel request" while the explore request of `export-csv` is waiting
- **THEN** the page shows no open request and offers "Start exploring" again

#### Scenario: Reply note
- **WHEN** a member opens the page of `export-csv`, which is in Exploring with no open request
- **THEN** a note beside the comment field says that posting asks an agent to reply

#### Scenario: Request lines in the thread
- **WHEN** a member asked for an explore request on `export-csv` and Fish took it and finished it with questions
- **THEN** the thread shows the member asking for exploring, Fish taking it and finishing it, followed by Fish's questions

#### Scenario: Archived change
- **WHEN** a member opens the page of the archived change `fix-login`
- **THEN** no request button and no "Cancel request" action are offered
