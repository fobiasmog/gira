## Purpose

Lets people ask for the next step of a change in Goalner, and lets agents that wait for work take each step, do it and report back on the change, so that no step has to be started from a terminal.

## ADDED Requirements

### Requirement: Requests for the steps of a change
A request SHALL ask for one step of a change, of the kind explore, propose, implement, archive or reply. Its state SHALL be waiting, taken, done, failed or cancelled; a request that is waiting or taken is open. A change SHALL have at most one open request. Goalner SHALL record who asked for each request and when, who took it and when, and who finished or cancelled it and when.

#### Scenario: One open request
- **WHEN** `export-csv` has a waiting explore request and a member asks for a propose request on it
- **THEN** the response is HTTP 422 with a validation error, and `export-csv` still has only the explore request

#### Scenario: Request after a finished one
- **WHEN** agent Fish finished the explore request of `export-csv`, and a member asks for a propose request on it
- **THEN** `export-csv` has a waiting propose request, and the explore request stays done

### Requirement: Ask for a step
Members SHALL be able to ask for an explore, propose, implement or archive request on an open change in any phase, optionally with a comment of 1 to 10,000 characters. The comment SHALL be posted on the change as the member's comment and SHALL NOT create a reply request (requirement "Reply requests"). The response SHALL be HTTP 201 with the request, which is waiting. When the change's open request is a reply request that is waiting, asking for another step SHALL cancel the reply request and create the new one. Asking for a step on a change with any other open request, or on an archived change, SHALL be refused with a validation error and SHALL change nothing. Asking for a reply request SHALL be refused with a validation error on the kind.

#### Scenario: Start exploring
- **WHEN** a member asks for an explore request on `export-csv`, which is in Idea and has no open request
- **THEN** the response is HTTP 201 with a waiting explore request asked for by the member, and `export-csv` is still in Idea

#### Scenario: With a comment
- **WHEN** a member asks for an implement request on `export-csv` with the comment "Start with the API."
- **THEN** the comment is posted on `export-csv` by the member, and the change's only open request is the waiting implement request

#### Scenario: Replacing a reply request
- **WHEN** a member's comment on `export-csv` created a reply request that is still waiting, and the member then asks for an implement request
- **THEN** the reply request is cancelled, and `export-csv` has a waiting implement request

#### Scenario: Taken request
- **WHEN** agent Fish has taken the reply request of `export-csv`, and a member asks for an implement request
- **THEN** the response is HTTP 422 with a validation error, and Fish's request stays taken

#### Scenario: Archived change
- **WHEN** a member asks for an explore request on the archived change `fix-login`
- **THEN** the response is HTTP 422 with a validation error, and no request is created

#### Scenario: Reply asked for directly
- **WHEN** a member asks for a request of the kind reply
- **THEN** the response is HTTP 422 with a validation error on the kind, and no request is created

### Requirement: Reply requests
When a person, as opposed to an agent (spec `agents`), comments on an open change that is not in Idea and has no open request, Goalner SHALL create a reply request on the change, asked for by that person. A comment by an agent, a comment on a change in Idea, a comment on a change with an open request, and a comment posted while asking for a step SHALL NOT create a request.

#### Scenario: Answer to an agent's questions
- **WHEN** agent Fish finished the explore request of `export-csv` with questions, and a member replies "No archived tasks." on `export-csv`
- **THEN** `export-csv` has a waiting reply request asked for by the member

#### Scenario: Agent's comment
- **WHEN** Fish comments on `export-csv`, which is in Exploring and has no open request
- **THEN** no request is created

#### Scenario: Comment in Idea
- **WHEN** a member comments on `fix-login`, which is in Idea
- **THEN** no request is created

#### Scenario: Comment while a request is taken
- **WHEN** Fish has taken the implement request of `export-csv` and a member comments on `export-csv`
- **THEN** no request is created, and the implement request stays taken by Fish

### Requirement: Take a request
A member SHALL be able to take a request of a project with one call. The call SHALL return the oldest request of the project that the caller took and has not finished, when there is one. Otherwise it SHALL mark the project's oldest waiting request as taken by the caller and return it. When no request is waiting, the response SHALL be HTTP 200 and SHALL say that there is no request, so that an agent cannot mistake it for a taken one. Two calls SHALL never take the same request. The returned request SHALL name its change and the change's phase. Taking an explore request SHALL move a change in Idea to Exploring, and taking an implement request SHALL move its change to Implementing, each recorded in the change's history as a move by the taker (spec `changes`, "Change history").

#### Scenario: Oldest waiting request
- **WHEN** TEST has a waiting explore request on `fix-login`, asked for yesterday, and a waiting implement request on `export-csv`, asked for today, and agent Fish takes a request
- **THEN** Fish gets the explore request of `fix-login`, now taken by Fish, `fix-login` is in Exploring, and the implement request is still waiting

#### Scenario: Nothing waiting
- **WHEN** Fish takes a request of TEST, which has no waiting request and none taken by Fish
- **THEN** the response is HTTP 200 and holds no request

#### Scenario: Resume
- **WHEN** Fish took the implement request of `export-csv` and has not finished it, and Fish takes a request again while another request is waiting
- **THEN** Fish gets the implement request of `export-csv` again, and the other request stays waiting

#### Scenario: Two agents at once
- **WHEN** agents Fish and Heron take a request of TEST at the same moment, and exactly one request is waiting
- **THEN** one of them gets it, and the other gets a response that holds no request

#### Scenario: Implement moves the phase
- **WHEN** Fish takes the waiting implement request of `export-csv`, which is in Proposed
- **THEN** `export-csv` is in Implementing, and its history lists Fish's move to Implementing

### Requirement: Finish a request
The member who took a request SHALL be able to finish it as done or failed, with a comment of 1 to 10,000 characters that SHALL be posted on the change as the taker's comment. Finishing SHALL be refused with a validation error, changing nothing, when the request is not taken, was taken by someone else, or comes without a comment. Finishing an archive request as done SHALL archive the change (spec `changes`, "Archive a change") after the comment is posted.

#### Scenario: Questions
- **WHEN** agent Fish finishes the explore request of `export-csv` as done with the comment "Two questions before I write the proposal: …"
- **THEN** the request is done, the comment is posted on `export-csv` by Fish, and `export-csv` is waiting for people

#### Scenario: Failed
- **WHEN** Fish finishes the implement request of `export-csv` as failed with the comment "The system tests fail on the CSV download."
- **THEN** the request is failed, and the comment is posted on `export-csv` by Fish

#### Scenario: Archive
- **WHEN** Fish finishes the archive request of `export-csv` as done with the comment "Archived the OpenSpec change and synced its specs."
- **THEN** the comment is posted on `export-csv`, and `export-csv` is archived

#### Scenario: Cancelled meanwhile
- **WHEN** a member cancelled the request that Fish took, and Fish then finishes it
- **THEN** the response is HTTP 422 with a validation error, and no comment is posted

#### Scenario: Someone else's request
- **WHEN** agent Heron finishes the request that Fish took
- **THEN** the response is HTTP 422 with a validation error, and the request stays taken by Fish

#### Scenario: No comment
- **WHEN** Fish finishes its request without a comment
- **THEN** the response is HTTP 422 with a validation error on the comment, and the request stays taken

### Requirement: Cancel a request
Members SHALL be able to cancel an open request of their project. Cancelling a request that is no longer open SHALL leave it as it is.

#### Scenario: Cancel a waiting request
- **WHEN** a member cancels the waiting explore request of `export-csv`
- **THEN** the request is cancelled by the member, and `export-csv` has no open request

#### Scenario: Cancel a taken request
- **WHEN** a member cancels the implement request of `export-csv` that agent Fish has taken
- **THEN** the request is cancelled, and Fish's next take does not return it

#### Scenario: Cancel a finished request
- **WHEN** a member cancels a request that Fish finished as done
- **THEN** the request stays done

### Requirement: Open request of a change
Change lists and opening a change (spec `changes`) SHALL include the change's open request, with its id, kind, state, who asked for it and when, and who took it and when, or `null` when the change has no open request.

#### Scenario: Taken request in the list
- **WHEN** agent Fish has taken the explore request of `export-csv`, and a member lists the open changes
- **THEN** `export-csv` is listed with its explore request, taken by Fish, with the times it was asked for and taken

#### Scenario: No open request
- **WHEN** a member opens `fix-login`, whose only request was cancelled
- **THEN** its open request is `null`
