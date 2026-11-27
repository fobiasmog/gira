## Purpose

Lets a machine prove who it is with a runner secret registered once, and lets it lease an agent and get a run token for it, so that nobody copies an agent's token to start or restart it.

## ADDED Requirements

### Requirement: Runners
A signed-in person SHALL be able to create a runner with a name of 1 to 100 characters, re-entering their current password. A wrong password SHALL create nothing and SHALL count as a failed attempt toward account lockout, as defined in `user-auth`; while the account is locked, creation SHALL be refused even with the correct password. The person SHALL be the runner's owner. The response SHALL contain the runner and its secret. The secret SHALL start with `glnr_runner_`, SHALL contain at least 160 bits of randomness, and SHALL NOT be retrievable afterwards: Goalner SHALL store only a one-way digest of it and SHALL keep it out of logs and error reports. A person SHALL have at most 10 runners, and SHALL be able to create at most 10 runners per hour. Requests over the hourly limit SHALL receive HTTP 429 and SHALL NOT be processed.

#### Scenario: Create
- **WHEN** Bob creates a runner named "laptop", entering his correct password
- **THEN** the response contains the runner and a secret starting with `glnr_runner_`, and the runner is listed among Bob's runners

#### Scenario: Wrong password
- **WHEN** Bob creates a runner with a wrong current password
- **THEN** no runner is created, and Bob's failed-attempt count increases by one

#### Scenario: Runner limit
- **WHEN** Bob, who has 10 runners, creates another
- **THEN** the request is rejected with a validation error, and no runner is created

### Requirement: List and revoke runners
The owner of a runner SHALL be able to list their runners, each with its name, the last four characters of its secret, when it was created, when it last contacted Goalner to within one minute, and the agents it holds a live lease of (requirement "Lease an agent"). The owner SHALL be able to revoke a runner without re-entering a password. Revoking SHALL end every lease of the runner at once, and its secret SHALL stop authenticating immediately. A runner SHALL also end when its owner's password is changed or reset. An ended runner SHALL NOT work again. Every request about a runner from anyone but its owner SHALL receive HTTP 404. Runners SHALL be handled only from a signed-in session: a request made with any token or runner secret SHALL receive HTTP 403 and have no effect.

#### Scenario: List
- **WHEN** Bob's runner "laptop" holds a lease of agent Fish, and Bob lists his runners
- **THEN** "laptop" is listed with the last four characters of its secret, its last contact and Fish, never with the whole secret

#### Scenario: Another person's runner
- **WHEN** Carol requests Bob's runner by id
- **THEN** the response is HTTP 404

#### Scenario: Revoke
- **WHEN** Bob revokes "laptop", which holds a lease of Fish
- **THEN** the next request with the runner's secret receives HTTP 401, and the next request with Fish's run token receives HTTP 401

#### Scenario: Password change
- **WHEN** Bob changes his password
- **THEN** every runner of Bob's stops authenticating, and their leases end

### Requirement: Runner authentication
The runner endpoints SHALL be those of this spec and of spec `agent-workspaces` that a runner calls. They SHALL be authenticated only by a runner secret, sent in the header `Authorization: Bearer <secret>`. A runner endpoint SHALL answer a request without a valid runner secret, including one with a session or an API token, with HTTP 401 and the JSON error envelope. Every other endpoint SHALL treat a runner secret as an unknown token. A runner SHALL be able to read its own name and its owner's name. Each runner secret SHALL be able to make at most 300 requests per minute, and a runner SHALL be able to lease agents at most 60 times per hour; requests over a limit SHALL receive HTTP 429 and SHALL NOT be processed. Runner endpoints SHALL NOT be part of the API document (spec `api-documentation`), and so SHALL NOT be tools of the MCP server.

#### Scenario: Runner secret on a project endpoint
- **WHEN** a client sends a valid runner secret to read the projects list
- **THEN** the response is HTTP 401 with the code `invalid_token`

#### Scenario: Agent token on a runner endpoint
- **WHEN** a client leases an agent with a valid agent token instead of a runner secret
- **THEN** the response is HTTP 401, and no lease is created

#### Scenario: Read itself
- **WHEN** Bob's runner "laptop" reads itself
- **THEN** the response names the runner "laptop" and its owner Bob

### Requirement: Lease an agent
A runner SHALL be able to lease an agent that its owner can see (spec `agents`, "Who can see and handle an agent") and that is not deleted. Any other agent SHALL receive HTTP 404, as for an agent that does not exist. The response SHALL be HTTP 201 and SHALL contain:
- the lease's id and the value of its run token (requirement "Run tokens"), which SHALL NOT be retrievable afterwards;
- the agent's id, name, model and instructions (spec `agents`, "Agent settings");
- the projects the run token reaches, each with its id and short name;
- the open change the agent is on, if any, with its project, id, name, phase and base branch (spec `changes`, "Base branch of a change"), the session of the agent's stint on it (spec `agent-workspaces`, "Session of a stint"), its workspace or `null`, and the request the agent took on it and has not finished, or `null`; or `null` when the agent is on no open change.

Leasing SHALL NOT change the agent, its change or its requests, and SHALL NOT count as a check-in.

#### Scenario: Free agent
- **WHEN** Bob's runner leases agent Fish, which belongs to TEST and is on no change
- **THEN** the response is HTTP 201 with a lease, a run token, Fish's name and settings, TEST with its short name, and no change

#### Scenario: Agent in the middle of a step
- **WHEN** Fish is on `export-csv`, whose workspace is on Bob's runner, and has taken its implement request, and Bob's runner leases Fish
- **THEN** the response names `export-csv` with its phase, base branch, session, workspace and the implement request

#### Scenario: Agent its owner cannot see
- **WHEN** Bob's runner leases agent Owl, which shares no non-archived project with Bob
- **THEN** the response is HTTP 404, and no lease is created

#### Scenario: Deleted agent
- **WHEN** Bob's runner leases agent Fish after Fish was deleted
- **THEN** the response is HTTP 404

### Requirement: One lease per agent
An agent SHALL have at most one live lease. Leasing an agent that has a live lease of another runner SHALL be refused with HTTP 409 and the code `agent_leased`, naming that runner and when its lease started, and SHALL change nothing. Leasing an agent that has a live lease of the same runner SHALL end that lease and create a new one. Leasing an agent that is on an open change whose workspace is active on another runner (spec `agent-workspaces`) SHALL be refused with HTTP 409 and the code `workspace_elsewhere`, naming that runner, and SHALL change nothing.

#### Scenario: Leased to another runner
- **WHEN** Fish has a live lease of Bob's runner "laptop", and Bob's runner "desktop" leases Fish
- **THEN** the response is HTTP 409 with the code `agent_leased`, naming "laptop" and when its lease started, and Fish keeps its lease of "laptop"

#### Scenario: Same runner again
- **WHEN** Fish has a live lease of "laptop", and "laptop" leases Fish again
- **THEN** the first lease has ended and its run token receives HTTP 401, and the new run token works

#### Scenario: Workspace on another runner
- **WHEN** Fish is on `export-csv`, whose workspace is active on "laptop", and Fish has no live lease, and "desktop" leases Fish
- **THEN** the response is HTTP 409 with the code `workspace_elsewhere`, naming "laptop", and no lease is created

### Requirement: Run tokens
A run token SHALL be an agent token (spec `agents`) of the leased agent, issued by the runner's owner. It SHALL have read-write access on both channels, the API and the MCP server, and SHALL reach what spec `agents`, "Agent token reach", gives a token of that issuer. Its value SHALL follow spec `api-tokens`, and SHALL be returned only in the lease's response. Issuing it SHALL need no password. Run tokens SHALL NOT be listed among the agent's tokens, and SHALL NOT count toward any limit on agent tokens (spec `agents`, "Issue agent tokens"). A run token SHALL stop authenticating when its lease ends, and SHALL NOT work again.

#### Scenario: Reach
- **WHEN** Bob's runner leases Fish, which belongs to TEST and OPS, and Bob is a member of TEST only
- **THEN** the run token's project list contains TEST and not OPS

#### Scenario: Attribution
- **WHEN** a comment is posted on `export-csv` with Fish's run token
- **THEN** the comment's author is Fish

#### Scenario: Not listed
- **WHEN** Fish has a live lease, and Carol lists Fish's tokens
- **THEN** the run token is not in the list

### Requirement: Renewing and ending a lease
Every take (spec `change-requests`, "Take a request") made with a run token SHALL renew its lease. A lease SHALL end, and stay ended, when:
- its runner releases it;
- it has not been renewed for the lease window, which SHALL be 5 minutes unless the server's configuration sets another number of seconds;
- its runner is revoked or ends;
- its agent is deleted;
- the same runner leases the agent again.

Releasing a lease that has already ended SHALL succeed and change nothing. Ending a lease SHALL NOT change the agent's change, its requests or its workspace: a request the agent took stays taken.

#### Scenario: Release
- **WHEN** Bob's runner releases its lease of Fish
- **THEN** Fish's run token receives HTTP 401 on its next request, and Fish can be leased again by any of Bob's runners

#### Scenario: Lapse
- **WHEN** Fish's run token made its last take 6 minutes ago, with the default lease window
- **THEN** the lease has ended, the run token receives HTTP 401, and another runner can lease Fish

#### Scenario: Taken request survives
- **WHEN** Fish took the implement request of `export-csv`, and its lease lapses
- **THEN** the implement request is still taken by Fish, and the next lease of Fish names it

#### Scenario: Agent deleted
- **WHEN** a member deletes Fish while it has a live lease
- **THEN** the lease has ended, and its run token receives HTTP 401

### Requirement: Leases in the agent list
The project's list of agents (spec `change-requests`, "Check-ins") SHALL include, for each agent, its live lease: the runner's name, the runner's owner and when the lease started, or `null` when the agent has no live lease.

#### Scenario: Running agent
- **WHEN** Fish has a live lease of Bob's runner "laptop", started at 14:05, and a member lists TEST's agents
- **THEN** Fish is listed with the runner "laptop", its owner Bob and 14:05
