## ADDED Requirements

### Requirement: Agent tokens follow the token rules
An agent token (spec `agents`) SHALL be a token whose owner is the agent. The following rules of this spec SHALL apply to it as to a personal token:
- authentication by header;
- the access level and attribution to the owner;
- the endpoints available to tokens;
- file downloads within the projects it reaches;
- storage and secrecy;
- the limit on requests per token.

Its issue, reach, channels, listing, revocation and lifetime SHALL follow spec `agents`. Agent tokens SHALL NOT appear in any user's list of personal tokens and SHALL NOT count toward any user's personal token limits.

#### Scenario: Read-only agent token writes
- **WHEN** a read-only token of agent Fish creates a task in GOAL
- **THEN** the response is HTTP 403 and no task is created

#### Scenario: Project administration
- **WHEN** a read-write token of agent Fish renames GOAL, invites someone, removes a member, adds a column, or lists or creates API tokens
- **THEN** each request receives HTTP 403 and nothing changes

#### Scenario: Not a personal token
- **WHEN** Bob, who issued two tokens for agent Fish, lists his API tokens
- **THEN** neither of Fish's tokens is listed, and they do not count toward Bob's limit of 20

#### Scenario: Stored value
- **WHEN** an agent token is issued
- **THEN** its value starts with `glnr_`, and only a one-way digest of it is stored
