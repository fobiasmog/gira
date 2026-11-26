## MODIFIED Requirements

### Requirement: Take a request
Only agents SHALL take requests; a person's attempt SHALL be refused with HTTP 403 and SHALL change nothing. An agent SHALL be able to take a request of a project with one call, which SHALL return the first of these that exists:
1. the oldest request of the project that the agent took and has not finished;
2. the waiting request of the change the agent is on;
3. when the agent is on no open change: the oldest waiting request of a change of the project that has the agent picked;
4. when the agent is on no open change: the oldest waiting request of a change of the project with no agent.

A request found in steps 2 to 4 SHALL be marked as taken by the agent, and in steps 3 and 4 the agent SHALL be on its change from then on. A request of a change that another agent is on or has picked SHALL never be returned, and no request of a blocked change (requirement "Full context") SHALL be returned at all. A request of a change whose workspace is active (spec `agent-workspaces`) SHALL be returned only to a take made with a run token of the runner that holds the workspace (spec `agent-runners`, "Run tokens"), and SHALL never be returned to any other take. When no request is found, the response SHALL be HTTP 200 and SHALL say that there is no request, so that an agent cannot mistake it for a taken one. Two calls SHALL never take the same request. The returned request SHALL name its change, the change's phase and base branch (spec `changes`, "Base branch of a change"), the session of the agent's stint on it (spec `agent-workspaces`, "Session of a stint"), and the change's workspace, or `null` (spec `agent-workspaces`, "Workspace in change responses"). Taking an explore request SHALL move a change in Idea to Exploring, and taking an implement request SHALL move its change to Implementing, each recorded in the change's history as a move by the agent (spec `changes`, "Change history").

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

#### Scenario: Workspace on another runner
- **WHEN** `export-csv` has no agent, a waiting implement request and an active workspace on Bob's runner "laptop", and agent Heron, free and leased to "desktop", takes a request with its run token
- **THEN** Heron gets no request, and the implement request stays waiting

#### Scenario: Token that is not a run token
- **WHEN** Fish is on `export-csv`, whose workspace is active on "laptop", `export-csv` has a waiting reply request, and Fish takes a request with a token that Bob issued for it
- **THEN** Fish gets no request, and the reply request stays waiting

#### Scenario: Base branch, session and workspace
- **WHEN** Fish, leased to "laptop", takes the reply request of `export-csv`, whose base branch is `main` and whose workspace is active on "laptop"
- **THEN** the returned request names `export-csv`, its phase, the base branch `main`, the session of Fish's stint and the workspace on "laptop"
