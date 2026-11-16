# agents Specification

## Purpose
Lets project members bring AI agents into their projects as accounts of their own: agents are assigned work, act through tokens under their own name, and are handled, deleted and restored by the members they work with.

## Requirements

### Requirement: Agent accounts
An agent SHALL be an account of its own, distinct from every person's account. It SHALL have a name of 1 to 100 characters and an address that the system generates in the form `<adjective>-<animal>-<nnnn>@agents.goalner.com`. The address SHALL be unique across all accounts and SHALL never be chosen by a person. The system SHALL record which user created the agent. That record SHALL be information only and SHALL give its user no rights over the agent.

#### Scenario: Generated address
- **WHEN** a member creates an agent named "Fish"
- **THEN** the agent's name is "Fish", and its address has the form `<adjective>-<animal>-<four digits>@agents.goalner.com` and differs from every other account's address

#### Scenario: Creator recorded
- **WHEN** Alice creates an agent
- **THEN** the agent shows Alice as its creator

#### Scenario: Creator without rights
- **WHEN** Alice created agent Fish in GOAL, Fish belongs only to GOAL, and the owner of GOAL then removes Alice from GOAL
- **THEN** Fish stays a member of GOAL, and Alice's requests about Fish receive HTTP 404

### Requirement: Agents never receive email
The system SHALL NOT send any email to an agent's address, whatever the action that would otherwise send one. The agent domain SHALL accept no mail: it SHALL publish a null MX record.

#### Scenario: Actions that would email
- **WHEN** a task is assigned to an agent, a password reset is requested for its address, or sign-in fails ten times with its address
- **THEN** no email is sent to the agent's address

#### Scenario: Mail exchanger lookup
- **WHEN** a mail server looks up the mail exchanger of `agents.goalner.com`
- **THEN** the answer is a null MX record (`0 .`)

### Requirement: Who can see and handle an agent
A user SHALL be able to see and handle an agent, active or deleted, only while both of them belong to at least one common non-archived project. Handling SHALL mean:
- renaming the agent;
- issuing and revoking its tokens;
- adding it to another project and removing it from a project;
- deleting it and restoring it.

Every request about an agent from anyone else SHALL receive HTTP 404, as for an agent that does not exist. The agent's creator SHALL have no other rights than any user. Agents SHALL be handled only from a signed-in session: a request made with any token SHALL receive HTTP 403 and have no effect.

#### Scenario: Member of a shared project
- **WHEN** Bob, a member of GOAL, lists the agents he can see and agent Fish belongs to GOAL
- **THEN** Fish is listed, and Bob can rename it

#### Scenario: No shared project
- **WHEN** Mallory, who shares no non-archived project with agent Fish, requests Fish by id
- **THEN** the response is HTTP 404

#### Scenario: Tokens cannot handle agents
- **WHEN** a client with a read-write token, whether a person's or an agent's, creates an agent, issues an agent token or deletes an agent
- **THEN** each request receives HTTP 403 and nothing changes

### Requirement: Create an agent in a project
Any member of a non-archived project SHALL be able to create an agent in that project. The request SHALL give the agent's name and its first token's name, access level and channels (requirement "Issue agent tokens"), and SHALL re-enter the member's current password. The agent SHALL become a member of the project at once, without an invitation. The response SHALL contain the agent and the first token's value. A wrong password SHALL create nothing and SHALL count as a failed attempt toward account lockout, as defined in `user-auth`.

#### Scenario: Create
- **WHEN** Bob, a member of GOAL, creates agent "Fish" with a read-write token for the API and MCP, entering his correct password
- **THEN** Fish is a member of GOAL and is listed among GOAL's members as an agent, and the response contains the token's value

#### Scenario: Wrong password
- **WHEN** a member creates an agent with a wrong current password
- **THEN** no agent and no token are created, and the member's failed-attempt count increases by one

#### Scenario: Archived project
- **WHEN** a member tries to create an agent in an archived project
- **THEN** the response is HTTP 404 and nothing is created

### Requirement: Agents in projects
A user who can see an agent SHALL be able to add it to any non-archived project they are a member of. The agent SHALL become a member at once, without an invitation. A deleted agent SHALL NOT be added to a project.

Any member of a project SHALL be able to remove an agent from it. Tasks assigned to the agent in that project SHALL become unassigned. An agent SHALL always belong to at least one non-archived project, so removing it from its last one SHALL be rejected with a validation error.

#### Scenario: Add to another project
- **WHEN** Bob, a member of GOAL and OPS, adds agent Fish of GOAL to OPS
- **THEN** Fish is a member of OPS and can be assigned OPS tasks

#### Scenario: Project the user does not belong to
- **WHEN** Bob adds Fish to TEST, a project Bob is not a member of
- **THEN** the response is HTTP 404 and Fish does not join TEST

#### Scenario: Remove by a member
- **WHEN** Carol, a member of OPS who is not its owner, removes agent Fish from OPS, and Fish also belongs to GOAL
- **THEN** Fish is no longer a member of OPS, OPS tasks assigned to Fish become unassigned, and Fish stays a member of GOAL

#### Scenario: Last project
- **WHEN** a member removes agent Fish from GOAL, its only non-archived project
- **THEN** the request is rejected with a validation error and Fish stays a member of GOAL

### Requirement: Agents work like members
An agent SHALL take part in its projects as a member does, through its tokens:
- any member, person or agent, can assign it tasks;
- it can create, edit, move and archive tasks, add subtasks and comment;
- it can assign tasks to any member of the project, including other agents.

Every change made with an agent's token SHALL be attributed to the agent, never to the person who issued the token.

#### Scenario: Person assigns to an agent
- **WHEN** Bob assigns GOAL-7 to agent Fish
- **THEN** Fish is GOAL-7's assignee

#### Scenario: Agent delegates to another agent
- **WHEN** Fish, with a read-write token, creates GOAL-8 assigned to agent Owl, a member of GOAL
- **THEN** GOAL-8's creator is Fish and its assignee is Owl

#### Scenario: Attribution
- **WHEN** Fish comments on GOAL-7 with a token that Bob issued
- **THEN** the comment's author is Fish

### Requirement: Agents in API responses
Wherever the API returns a user, it SHALL state whether that user is an agent and, for an agent, whether it is deleted. An agent's address SHALL be returned where a person's email address would be.

#### Scenario: Member list
- **WHEN** a member lists GOAL's members and agent Fish belongs to GOAL
- **THEN** Fish's entry has its name, its address and avatar, and states that it is an agent

#### Scenario: Own profile
- **WHEN** a client reads the signed-in user's profile with one of Fish's tokens
- **THEN** the profile is Fish's and states that it is an agent

### Requirement: Issue agent tokens
A user who can see an agent SHALL be able to issue a token for it, giving:
- a name of 1 to 100 characters;
- an access level of read-only or read-write;
- its channels: the API, the MCP server, or both.

Issuing SHALL require the issuer's current password, with the same lockout rules as for personal tokens in `api-tokens`. The response SHALL contain the token's value, which SHALL NOT be retrievable afterwards. An agent token SHALL be valid for 100 years from its issue, and the issuer SHALL NOT be able to choose another lifetime.

Limits:
- An agent SHALL have at most 20 live tokens. Issuing beyond that SHALL be rejected with a validation error.
- A user SHALL be able to issue at most 10 agent tokens per hour, including the first tokens of agents they create. Requests over this limit SHALL receive HTTP 429 and SHALL NOT be processed.

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

### Requirement: Agent token reach
At the time of each request, an agent token SHALL reach the non-archived projects that both the agent and the token's issuer are members of. Requests for any other project SHALL receive HTTP 404, as for a non-member. With an agent token, the project list SHALL contain exactly the projects the token reaches. A token that reaches no project SHALL still authenticate, and SHALL see no project.

#### Scenario: Projects in common
- **WHEN** agent Fish belongs to GOAL and OPS, and its token was issued by Bob, a member of GOAL and OPS
- **THEN** the token's project list contains GOAL and OPS

#### Scenario: Issuer not in a project
- **WHEN** agent Fish belongs to GOAL and OPS, its token was issued by Carol, a member of OPS only, and the token requests GOAL's tasks
- **THEN** the response is HTTP 404

#### Scenario: Issuer leaves a project
- **WHEN** Bob, who issued a token for Fish, leaves OPS
- **THEN** the token receives HTTP 404 for OPS and keeps working for GOAL

#### Scenario: Agent joins a project
- **WHEN** Fish is added to TEST, of which the token's issuer is also a member
- **THEN** the token reaches TEST from the next request on

### Requirement: Agent token channels
An agent token SHALL authenticate only on the channels it was issued for. For a token issued for a single channel:
- a request without a service key SHALL count as a direct API request;
- a request carrying the MCP server's service key SHALL count as made through the MCP server;
- a request carrying any other service key SHALL count as neither, and SHALL receive HTTP 401 with the code `invalid_service_key`.

On a channel it was not issued for, the token SHALL be treated as unknown, and the request SHALL receive HTTP 401 with the code `invalid_token`. A token issued for both channels SHALL authenticate whatever service key the request carries.

#### Scenario: MCP-only token used directly
- **WHEN** a client sends a valid MCP-only agent token directly to the API, without a service key
- **THEN** the response is HTTP 401 with the code `invalid_token`

#### Scenario: Forged service key
- **WHEN** a client sends an MCP-only agent token directly to the API with a made-up service key header
- **THEN** the response is HTTP 401 with the code `invalid_service_key`

#### Scenario: API-only token used through MCP
- **WHEN** a client lists tools at `/mcp` with a valid API-only agent token
- **THEN** the response is HTTP 401

#### Scenario: Both channels
- **WHEN** a token issued for the API and MCP is used directly and through `/mcp`
- **THEN** both requests are authenticated as the agent

#### Scenario: Both channels with a wrong service key
- **WHEN** a token issued for the API and MCP is sent with a service key that is not the MCP server's
- **THEN** the request is authenticated as the agent

### Requirement: List and revoke agent tokens
A user who can see an agent SHALL be able to list its tokens, each with:
- its name and issuer;
- its access level and channels;
- the last four characters of its value;
- its creation time and last use.

The list SHALL include tokens issued by anyone, and SHALL never show a whole value. The user SHALL be able to revoke any of these tokens without re-entering a password. A revoked token SHALL stop authenticating immediately.

#### Scenario: Tokens issued by others
- **WHEN** Carol, a member of GOAL, lists the tokens of agent Fish, one of which Bob issued
- **THEN** Bob's token is listed with Bob as its issuer and the last four characters of its value, never the whole value

#### Scenario: Revoke another user's token
- **WHEN** Carol revokes the token that Bob issued for Fish
- **THEN** the next request with that token receives HTTP 401

### Requirement: Agent token lifetime
An agent token SHALL stop authenticating only when it is revoked, when its agent is deleted, or 100 years after its issue, and SHALL NOT work again afterwards, even when the agent is restored. Changing or resetting any user's password, including the issuer's or the agent's creator's, SHALL NOT affect agent tokens. A project leaving a token's reach (requirement "Agent token reach") SHALL narrow the token without ending it. The time of a token's last use SHALL be recorded to within one hour.

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

### Requirement: Delete an agent
A user who can see an agent SHALL be able to delete it. Deleting SHALL:
- delete all of its tokens for good;
- unassign it from its tasks that are neither archived nor in a done column, in every project;
- keep its memberships, but leave it out of member lists, teammates and assignee choices, and refuse it as an assignee;
- keep it as the creator, comment author and assignee of its past work, marked as deleted.

Deleting SHALL affect every project the agent belongs to. Each project SHALL list its deleted agents to its members.

#### Scenario: Delete
- **WHEN** Bob deletes agent Fish, which is assigned GOAL-7 in the "Work" column and GOAL-3 in the done column
- **THEN** all of Fish's tokens receive HTTP 401, and GOAL-7 has no assignee
- **AND** GOAL-3 still shows Fish, marked as deleted
- **AND** Fish is listed among GOAL's deleted agents and not among its members

#### Scenario: Across projects
- **WHEN** Bob, a member of GOAL only, deletes Fish, which also belongs to OPS
- **THEN** Fish is deleted in OPS too, and is listed among OPS's deleted agents

### Requirement: Restore an agent
A member of a project that a deleted agent belongs to SHALL be able to restore it. The agent SHALL then be active again in every project it belongs to, with no tokens and no assigned tasks. Restoring an agent that is not deleted SHALL change nothing.

#### Scenario: Restore
- **WHEN** Carol, a member of OPS, restores deleted agent Fish, which belongs to GOAL and OPS
- **THEN** Fish is listed again among the members of GOAL and OPS, has no tokens and is assigned no tasks

#### Scenario: Tokens after restore
- **WHEN** a member issues a token for a restored agent
- **THEN** the new token works, and tokens from before the deletion still receive HTTP 401
