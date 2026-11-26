## ADDED Requirements

### Requirement: Agent settings
An agent SHALL have a model and instructions, each optional. The model SHALL be 1 to 100 characters of Latin letters, digits, `.`, `-` and `_`, or `null`. The instructions SHALL be text of 1 to 10,000 characters, stored and returned exactly as written, or `null`. Both SHALL be given when the agent is created or set later by anyone who can handle the agent (requirement "Who can see and handle an agent"). Both SHALL be returned with the agent to those who can see it, and to runners that lease it (spec `agent-runners`, "Lease an agent").

#### Scenario: Set settings
- **WHEN** Bob sets agent Fish's model to `opus` and its instructions to "Keep commits small."
- **THEN** Fish's model is `opus` and its instructions are "Keep commits small.", and the next lease of Fish names both

#### Scenario: Clear the model
- **WHEN** Bob clears Fish's model
- **THEN** Fish's model is `null`

#### Scenario: Invalid model
- **WHEN** Bob sets Fish's model to `opus 4`
- **THEN** the request is rejected with a validation error on the model, and Fish's model is unchanged

## MODIFIED Requirements

### Requirement: Who can see and handle an agent
A user SHALL be able to see and handle an agent, active or deleted, only while both of them belong to at least one common non-archived project. Handling SHALL mean:
- editing the agent's name, model and instructions (requirement "Agent settings");
- issuing and revoking its tokens;
- adding it to another project and removing it from a project;
- deleting it and restoring it.

Every request about an agent from anyone else SHALL receive HTTP 404, as for an agent that does not exist. The agent's creator SHALL have no other rights than any user. Agents SHALL be handled only from a signed-in session: a request made with any token SHALL receive HTTP 403 and have no effect. Leasing an agent to a runner (spec `agent-runners`) SHALL NOT count as handling it.

#### Scenario: Member of a shared project
- **WHEN** Bob, a member of GOAL, lists the agents he can see and agent Fish belongs to GOAL
- **THEN** Fish is listed, and Bob can edit its name, model and instructions

#### Scenario: No shared project
- **WHEN** Mallory, who shares no non-archived project with agent Fish, requests Fish by id
- **THEN** the response is HTTP 404

#### Scenario: Tokens cannot handle agents
- **WHEN** a client with a read-write token, whether a person's or an agent's, creates an agent, issues an agent token or deletes an agent
- **THEN** each request receives HTTP 403 and nothing changes

### Requirement: Create an agent in a project
Any member of a non-archived project SHALL be able to create an agent in that project, giving its name and, optionally, its model and instructions (requirement "Agent settings"). Creating an agent SHALL issue no token and SHALL NOT ask for a password. The agent SHALL become a member of the project at once, without an invitation. The response SHALL contain the agent.

#### Scenario: Create
- **WHEN** Bob, a member of GOAL, creates agent "Fish"
- **THEN** Fish is a member of GOAL and is listed among GOAL's members as an agent, and Fish has no tokens

#### Scenario: With settings
- **WHEN** Bob creates agent "Heron" with the model `sonnet` and the instructions "Ask before adding gems."
- **THEN** Heron is a member of GOAL with that model and those instructions

#### Scenario: Wrong password
- **WHEN** a member creates agent "Owl", and the request also carries a wrong current password
- **THEN** Owl is created, and the member's failed-attempt count is unchanged, since creating an agent asks for no password

#### Scenario: Archived project
- **WHEN** a member tries to create an agent in an archived project
- **THEN** the response is HTTP 404 and nothing is created

### Requirement: Issue agent tokens
A user who can see an agent SHALL be able to issue a token for it, giving:
- a name of 1 to 100 characters;
- an access level of read-only or read-write;
- its channels: the API, the MCP server, or both.

Issuing SHALL require the issuer's current password, with the same lockout rules as for personal tokens in `api-tokens`. The response SHALL contain the token's value, which SHALL NOT be retrievable afterwards. An agent token SHALL be valid for 100 years from its issue, and the issuer SHALL NOT be able to choose another lifetime.

Limits:
- An agent SHALL have at most 20 live tokens. Issuing beyond that SHALL be rejected with a validation error.
- A user SHALL be able to issue at most 10 agent tokens per hour. Requests over this limit SHALL receive HTTP 429 and SHALL NOT be processed.

Run tokens (spec `agent-runners`, "Run tokens") SHALL NOT be issued this way, and SHALL NOT count toward these limits.

#### Scenario: Issue
- **WHEN** Bob, who shares GOAL with agent Fish, issues a read-only token named "runner" for MCP only, entering his correct password
- **THEN** the response contains the token's value, name, access level and channels, the token is valid for 100 years, and it is listed among Fish's tokens with Bob as its issuer

#### Scenario: Wrong password
- **WHEN** a user issues an agent token with a wrong current password
- **THEN** no token is created and the user's failed-attempt count increases by one

#### Scenario: Token limit
- **WHEN** a user issues a token for an agent that already has 20 live tokens
- **THEN** the request is rejected with a validation error and no token is created

#### Scenario: Hourly limit
- **WHEN** a user requests an eleventh agent token within one hour
- **THEN** the request receives HTTP 429 and no token is created

#### Scenario: Run tokens do not count
- **WHEN** agent Fish has 20 live tokens issued by people, and Bob's runner leases Fish
- **THEN** the lease succeeds with a run token

### Requirement: List and revoke agent tokens
A user who can see an agent SHALL be able to list its tokens, each with:
- its name and issuer;
- its access level and channels;
- the last four characters of its value;
- its creation time and last use.

The list SHALL include tokens issued by anyone, except run tokens (spec `agent-runners`), and SHALL never show a whole value. The user SHALL be able to revoke any of these tokens without re-entering a password. A revoked token SHALL stop authenticating immediately.

#### Scenario: Tokens issued by others
- **WHEN** Carol, a member of GOAL, lists the tokens of agent Fish, one of which Bob issued
- **THEN** Bob's token is listed with Bob as its issuer and the last four characters of its value, never the whole value

#### Scenario: Revoke another user's token
- **WHEN** Carol revokes the token that Bob issued for Fish
- **THEN** the next request with that token receives HTTP 401

#### Scenario: Run token left out
- **WHEN** Fish has a live lease, and Carol lists Fish's tokens
- **THEN** the lease's run token is not listed

### Requirement: Agent token lifetime
An agent token issued by a person SHALL stop authenticating only when it is revoked, when its agent is deleted, or 100 years after its issue, and SHALL NOT work again afterwards, even when the agent is restored. Changing or resetting any user's password, including the issuer's or the agent's creator's, SHALL NOT affect agent tokens issued by people. A project leaving a token's reach (requirement "Agent token reach") SHALL narrow the token without ending it. The time of a token's last use SHALL be recorded to within one hour. A run token's lifetime SHALL follow spec `agent-runners`, "Renewing and ending a lease".

#### Scenario: Issuer changes password
- **WHEN** Bob, who issued a token for Fish, changes his password
- **THEN** the token keeps working

#### Scenario: Long after a personal token would have expired
- **WHEN** a token issued 400 days ago, and never revoked, is used
- **THEN** the request is authenticated as the agent

#### Scenario: A hundred years
- **WHEN** a token is used more than 100 years after it was issued
- **THEN** the request receives HTTP 401

#### Scenario: Deleted and restored
- **WHEN** agent Fish is deleted and later restored
- **THEN** every token issued for Fish before the deletion receives HTTP 401

#### Scenario: Last use
- **WHEN** an agent token is used to make a request
- **THEN** the agent's token list shows a last use no more than one hour before that request

#### Scenario: Run token ends with its lease
- **WHEN** Bob's runner releases its lease of Fish
- **THEN** the lease's run token receives HTTP 401, while Fish's tokens issued by people keep working
