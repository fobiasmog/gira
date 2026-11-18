## Purpose

Lets people ask for the next step of a change in Goalner, and lets a pool of agents take those steps, one agent per change from its first step until it is archived, so that no step has to be started from a terminal and the agent that asked a question gets its answer. An agent whose context fills up stops, and the change waits for people.

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

### Requirement: Agent of a change
A change SHALL have at most one agent (spec `agents`), which is either picked or on the change. Members SHALL be able to pick an agent of the project for an open change when creating it (spec `changes`, "Create a change") or later, and to clear the pick so that the change is for any free agent, while no agent is on the change. Picking SHALL NOT ask for any step, and the idea SHALL stay editable while the change is in Idea. An agent SHALL be on a change from when it takes the change's first request (requirement "Take a request") until the change is archived or the agent is released (requirement "Release an agent"). An agent SHALL be on at most one open change, in any project. Picking someone who is not an agent member of the project, or a deleted agent, and changing the pick while an agent is on the change, SHALL be refused with a validation error and SHALL change nothing.

#### Scenario: Pick when creating
- **WHEN** a member creates `add-tags` with the idea "Tags on tasks." and picks agent Fish, and Fish is free and takes a request of TEST
- **THEN** `add-tags` is in Idea with Fish picked, its idea can still be edited, and Fish's take returns no request

#### Scenario: Move to another agent
- **WHEN** `add-tags` has Fish picked and a waiting explore request, and a member picks Heron instead
- **THEN** `add-tags` has Heron picked, and Fish's next take does not return its request

#### Scenario: Back to any free agent
- **WHEN** a member clears the pick of `add-tags`, which has Fish picked
- **THEN** `add-tags` has no agent, and its waiting request is in the shared pool

#### Scenario: Agent on the change
- **WHEN** Fish is on `export-csv`, and a member picks Heron for `export-csv`
- **THEN** the response is HTTP 422 with a validation error, and Fish stays on `export-csv`

#### Scenario: Not an agent
- **WHEN** a member picks the person Bob as the agent of `add-tags`
- **THEN** the response is HTTP 422 with a validation error on the agent, and `add-tags` is unchanged

### Requirement: Release an agent
Members SHALL be able to release the agent of an open change. Releasing SHALL cancel the change's taken request, if it has one, end its block (requirement "Full context"), and leave the change with no agent, so that its waiting request, if it has one, is in the shared pool. Releasing a change with no agent SHALL leave it as it is.

#### Scenario: Release while waiting for people
- **WHEN** Fish is on `export-csv`, which has no open request, and a member releases Fish
- **THEN** `export-csv` has no agent, Fish is free, and the next request asked for on `export-csv` goes to the shared pool

#### Scenario: Release during a step
- **WHEN** Fish has taken the implement request of `export-csv`, and a member releases Fish
- **THEN** the implement request is cancelled by the member, `export-csv` has no agent, and Fish's next take does not return the request

### Requirement: Full context
An agent SHALL be able to report that its context is full. When the agent is on an open change of the project, Goalner SHALL block the change, record the block in the change's history (spec `changes`, "Change history"), and answer that the agent is blocked; the change's taken request SHALL stay taken. Otherwise Goalner SHALL answer that the agent is not blocked and change nothing. A blocked change SHALL give its agent no request (requirement "Take a request") until a member releases the agent (requirement "Release an agent") or the change is archived. Only agents SHALL report a full context; a person's report SHALL be refused with HTTP 403.

#### Scenario: Full during a step
- **WHEN** Fish is on `export-csv` with its implement request taken, and Fish reports that its context is full
- **THEN** the answer says Fish is blocked, `export-csv` is blocked and waiting for people, its history lists the block, and its implement request is still taken by Fish

#### Scenario: Full while free
- **WHEN** Heron is on no change and reports that its context is full
- **THEN** the answer says Heron is not blocked, and nothing changes

#### Scenario: Release after a block
- **WHEN** `export-csv` is blocked with Fish on it, a member releases Fish and asks for an implement request, and agent Heron, free, takes a request
- **THEN** Heron gets the implement request and is on `export-csv`, which is no longer blocked

### Requirement: Reply requests
When a person, as opposed to an agent (spec `agents`), comments on an open change that is not in Idea and has no open request, Goalner SHALL create a reply request on the change, asked for by that person. A comment by an agent, a comment on a change in Idea, a comment on a change with an open request, and a comment posted while asking for a step SHALL NOT create a request; a person's comment posted while a request is taken is answered when that request finishes (requirement "Finish a request").

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
- **THEN** no request is created yet, and the implement request stays taken by Fish

### Requirement: Take a request
Only agents SHALL take requests; a person's attempt SHALL be refused with HTTP 403 and SHALL change nothing. An agent SHALL be able to take a request of a project with one call, which SHALL return the first of these that exists:
1. the oldest request of the project that the agent took and has not finished;
2. the waiting request of the change the agent is on;
3. when the agent is on no open change: the oldest waiting request of a change of the project that has the agent picked;
4. when the agent is on no open change: the oldest waiting request of a change of the project with no agent.

A request found in steps 2 to 4 SHALL be marked as taken by the agent, and in steps 3 and 4 the agent SHALL be on its change from then on. A request of a change that another agent is on or has picked SHALL never be returned, and no request of a blocked change (requirement "Full context") SHALL be returned at all. When no request is found, the response SHALL be HTTP 200 and SHALL say that there is no request, so that an agent cannot mistake it for a taken one. Two calls SHALL never take the same request. The returned request SHALL name its change and the change's phase. Taking an explore request SHALL move a change in Idea to Exploring, and taking an implement request SHALL move its change to Implementing, each recorded in the change's history as a move by the agent (spec `changes`, "Change history").

#### Scenario: Oldest in the shared pool
- **WHEN** TEST has waiting explore requests on `fix-login`, asked for yesterday, and on `export-csv`, asked for today, neither with an agent, and agent Fish, on no change, takes a request
- **THEN** Fish gets the explore request of `fix-login`, now taken by Fish, Fish is on `fix-login`, `fix-login` is in Exploring, and the request on `export-csv` is still waiting

#### Scenario: Nothing waiting
- **WHEN** Fish takes a request of TEST, which has no waiting request and none taken by Fish
- **THEN** the response is HTTP 200 and holds no request

#### Scenario: Resume
- **WHEN** Fish took the implement request of `export-csv` and has not finished it, and Fish takes a request again
- **THEN** Fish gets the implement request of `export-csv` again

#### Scenario: Reply goes to the change's agent
- **WHEN** Fish is on `export-csv`, which has a waiting reply request, Heron is free, and Heron takes a request and then Fish does
- **THEN** Heron gets no request, and Fish gets the reply request

#### Scenario: Busy agent
- **WHEN** Fish is on `export-csv`, which has no waiting request, and `rename-labels`, with no agent, has a waiting explore request, and Fish takes a request
- **THEN** Fish gets no request, and the request on `rename-labels` stays waiting

#### Scenario: Own queue first
- **WHEN** Fish is free, `add-tags` has Fish picked and a waiting explore request asked for today, and `rename-labels` has no agent and a waiting explore request asked for yesterday, and Fish takes a request
- **THEN** Fish gets the request of `add-tags`, and Fish is on `add-tags`

#### Scenario: Picked for another agent
- **WHEN** `add-tags` has Fish picked and a waiting explore request, no other request is waiting, and Heron, free, takes a request
- **THEN** Heron gets no request

#### Scenario: Two agents at once
- **WHEN** agents Fish and Heron, both free, take a request of TEST at the same moment, and exactly one request is waiting, on a change with no agent
- **THEN** one of them gets it and is on its change, and the other gets a response that holds no request

#### Scenario: Implement moves the phase
- **WHEN** Fish takes the waiting implement request of `export-csv`, which is in Proposed and has Fish on it
- **THEN** `export-csv` is in Implementing, and its history lists Fish's move to Implementing

#### Scenario: A person takes
- **WHEN** a member takes a request of TEST, which has a waiting request
- **THEN** the response is HTTP 403, and the request stays waiting

#### Scenario: Blocked change
- **WHEN** Fish's change `export-csv` is blocked with its implement request taken by Fish, and Fish takes a request
- **THEN** Fish gets no request, and the implement request stays taken

### Requirement: Finish a request
The agent that took a request SHALL be able to finish it as done or failed, with a comment of 1 to 10,000 characters that SHALL be posted on the change as the agent's comment. Finishing SHALL be refused with a validation error, changing nothing, when the request is not taken, was taken by someone else, or comes without a comment. Finishing an archive request as done SHALL archive the change (spec `changes`, "Archive a change") after the comment is posted. Otherwise, when a person commented on the change after the request was taken, finishing SHALL create a reply request asked for by the author of the newest such comment.

#### Scenario: Questions
- **WHEN** agent Fish finishes the explore request of `export-csv` as done with the comment "Two questions before I write the proposal: …"
- **THEN** the request is done, the comment is posted on `export-csv` by Fish, and `export-csv` is waiting for people

#### Scenario: Failed
- **WHEN** Fish finishes the implement request of `export-csv` as failed with the comment "The system tests fail on the CSV download."
- **THEN** the request is failed, and the comment is posted on `export-csv` by Fish

#### Scenario: Comment while working
- **WHEN** Fish took the implement request of `export-csv` at 14:05, a member commented "Also handle empty files." at 14:20, and Fish finishes the request as done at 15:00
- **THEN** Fish's comment is posted, and `export-csv` has a waiting reply request asked for by the member

#### Scenario: Archive
- **WHEN** Fish finishes the archive request of `export-csv` as done with the comment "Archived the OpenSpec change and synced its specs."
- **THEN** the comment is posted on `export-csv`, `export-csv` is archived, and Fish is free

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
Members SHALL be able to cancel an open request of their project. Cancelling a request that is no longer open SHALL leave it as it is. Cancelling SHALL NOT change the change's agent.

#### Scenario: Cancel a waiting request
- **WHEN** a member cancels the waiting explore request of `export-csv`
- **THEN** the request is cancelled by the member, and `export-csv` has no open request

#### Scenario: Cancel a taken request
- **WHEN** a member cancels the implement request of `export-csv` that agent Fish has taken
- **THEN** the request is cancelled, Fish's next take does not return it, and Fish is still on `export-csv`

#### Scenario: Cancel a finished request
- **WHEN** a member cancels a request that Fish finished as done
- **THEN** the request stays done

### Requirement: Check-ins
Every take (requirement "Take a request") SHALL record its time as the agent's last check-in in that project, whether it returns a request or not. An agent SHALL be online in a project while its last check-in there is less than 3 minutes old, and offline otherwise, including when it has never checked in. The project's list of agents (spec `agents`) SHALL include, for each agent, its last check-in, whether it is online, and the open change it is on, if any.

#### Scenario: Online
- **WHEN** Fish took a request of TEST a minute ago and got none, and a member lists TEST's agents
- **THEN** Fish is listed as online, with that check-in time and no change

#### Scenario: Offline
- **WHEN** Owl's last take in TEST was two hours ago, and a member lists TEST's agents
- **THEN** Owl is listed as offline, with that check-in time

#### Scenario: On a change
- **WHEN** Fish is on `export-csv`, and a member lists TEST's agents
- **THEN** Fish is listed with `export-csv` as the change it is on

### Requirement: Open request and agent of a change
Change lists and opening a change (spec `changes`) SHALL include the change's open request, with its id, kind, state, who asked for it and when, and who took it and when, or `null` when the change has no open request. They SHALL also include the change's agent, whether it is picked or on the change, and since when the change is blocked, if it is, or `null` when the change has no agent.

#### Scenario: Taken request in the list
- **WHEN** agent Fish has taken the explore request of `export-csv`, and a member lists the open changes
- **THEN** `export-csv` is listed with its explore request, taken by Fish, with the times it was asked for and taken, and with Fish on the change

#### Scenario: No open request
- **WHEN** a member opens `fix-login`, whose only request was cancelled
- **THEN** its open request is `null`

#### Scenario: Picked agent
- **WHEN** a member opens `add-tags`, which has Fish picked
- **THEN** its agent is Fish, picked and not yet on the change
