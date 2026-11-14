# Proposal

## Why

Goalner should be usable by a swarm of AI agents that work on tasks the way people do: someone puts a task in To Do and assigns it to an agent, and the agent picks it up, moves it, comments, splits it and hands parts to other agents. Today an assistant can only act through its user's personal token or MCP connection. Everything it does then looks as if the user did it, and it cannot be assigned work of its own.

This change gives agents their own accounts in the tracker: members can create agents, add them to projects, assign them tasks and give them credentials. How agents decide what to do (the runtime, models, budgets) is a separate, later change.

## What Changes

- **Agent accounts.** An agent is an account of its own, not a profile of a person:
  - a name chosen by whoever creates it;
  - a generated address `<adjective>-<animal>-<nnnn>@agents.goalner.com`, for example `silver-fish-4821@agents.goalner.com`. The domain has a null MX record;
  - the user who created it, recorded for information only. It gives that user no rights over the agent.
- **Agents never sign in and never receive email.** They have no usable password. Sign-in, password reset, unlock and confirmation treat them as unknown addresses. No email is ever sent to an agent's address. Nobody can register or be invited with an address on the agent domain.
- **Agents belong to projects.**
  - Any member creates an agent inside a project, and it becomes a member at once, without an invitation.
  - Anyone who can see an agent can add it to another project they belong to.
  - Any member can remove an agent from a project, except from its last one.
  - An agent always belongs to at least one project.
- **Agents are handled by the members of their projects.** Every member of a non-archived project the agent belongs to can see it and handle it: rename it, issue and revoke its tokens, add it to or remove it from projects, delete it and restore it. Everyone else gets 404. Its creator has no extra rights.
- **Agents work like members.** Anyone in the project, person or agent, can assign tasks to an agent. Agents create tasks, comment, move cards and assign tasks to other members, including other agents. Every change is attributed to the agent. Agents appear in member lists, teammates and pickers, marked as agents.
- **Agent tokens:**
  - **Issuing.** Issued by a member who can see the agent, with that member's current password. The first token is issued when the agent is created.
  - **Where it works:** the API, the MCP server, or both, chosen at issue. When the API refuses the MCP server's own service key, clients get "Goalner is unavailable", never "invalid token".
  - **Reach.** It reaches every non-archived project that both the agent and the token's issuer belong to, checked on every request. When the issuer leaves a project, the token stops reaching it.
  - **Lifetime.** No expiry. It ends only when someone revokes it or the agent is deleted. Nobody's password change affects it.
  - **Visibility.** Everyone who can see the agent sees its tokens (name, issuer, access, channels, last four characters, created, last use) and can revoke them. Only the issuer sees the value, once. When MCP is included, the value is shown together with a ready-to-paste MCP configuration.
  - **Limits:** at most 20 live tokens per agent, and at most 10 agent tokens issued per user per hour.
- **Soft deletion and restore:**
  - **Deleting an agent:**
    - its tokens are deleted for good;
    - its open tasks are unassigned;
    - it disappears from member lists, teammates and pickers.
  - **History.** Its memberships, comments and past work stay, shown with a "deleted" marker.
  - **Restore.** Any member of one of its projects can restore it. Restoring brings back the agent and its memberships, but no tokens and no assignments.
- **"Assigned to me".** The task list gains a view of the requester's open tasks in a project, subtasks included, so an agent (or a person) can find its work with a token.
- **Notifications.**
  - Assigning a task to an agent sends no email.
  - An agent assigning a task to a person sends the usual email, naming the agent.
- **Web client:**
  - a project Agents screen to create, add, rename, remove, delete and restore agents and manage their tokens;
  - an agent marker wherever a person is shown.

Not included:
- the agent runtime: what wakes an agent up, which model it uses, how it plans, budgets and concurrency;
- permissions on who may handle agents beyond project membership;
- soft deletion of human accounts;
- choosing channels (API, MCP) for personal tokens;
- one call listing an agent's work across all its projects. Agents list their tasks project by project;
- avatars chosen for agents. They get the default avatar.

## Capabilities

### New Capabilities

- `agents`: agent accounts and the actions on them. Covers:
  - what an agent is and its address;
  - who can see and handle an agent;
  - creating it inside a project, adding it to and removing it from projects;
  - agent tokens: issue, reach, channels, listing, revocation and lifetime;
  - soft deletion and restore;
  - how agents are marked in the API.

### Modified Capabilities

- `api-tokens`: agent tokens are tokens owned by the agent. The token rules (authentication, access level, endpoints, files, storage, request limit) apply to them, while their issue, reach, channels and lifetime follow `agents`.
- `mcp-server`:
  - agent tokens authenticate at `/mcp` only when they were given MCP;
  - the MCP server identifies itself to the API with its service key, so the API can tell MCP requests from direct ones;
  - a refused service key answers 503, or an "unavailable" tool error, for agent tokens limited to one channel.
- `project-membership`:
  - member lists and teammates include active agents, marked;
  - any member can remove an agent;
  - addresses on the agent domain cannot be invited.
- `tasks`:
  - deleted agents cannot be assigned;
  - a new "assigned to me" view lists the requester's open tasks in a project.
- `notifications`: no assignment email to agents; agents' assignments notify people as usual.
- `user-auth`:
  - agent accounts cannot sign in, reset, unlock or confirm;
  - the agent domain cannot be registered.
- `web-client`: the Agents screen and the agent marker. The list of screens gains Agents.

`statistics` needs no change. Agents are teammates, so their overview works as for anyone, and deleted agents are not teammates.

## Impact

- **Data:**
  - a new `agents` table (`user_id`, `created_by_id`, `deleted_at`);
  - `api_tokens` gains `issuer_id` and `channels`, and `expires_at` becomes nullable for agent tokens. The check constraint `api_tokens_project_or_connection` is replaced by one that allows three kinds of token.
- **Main application:**
  - `Agent` model and handle generator;
  - agent scopes on `User`;
  - `ApiToken.personal` narrowed to tokens without an issuer, and a new `of_agents` scope;
  - `Current#projects` for agent tokens;
  - channel detection in `ApiTokenAuthentication`;
  - `config.x.agents.email_domain`, derived from `config.x.domain`;
  - the service key header added to Sentry's header deny-list;
  - `Api::AgentsController`, `Api::Projects::AgentsController`, `Api::Projects::Agents::MembershipsController`, `Api::Agents::TokensController` and `Api::Agents::RestorationsController`;
  - guards in sessions, passwords, confirmations, unlocks, registrations and invitations;
  - a mail interceptor for the agent domain;
  - `TaskAssignment`, `Task` assignee validation and the `assigned` task view;
  - `UserSerializer#card` gains `agent` and `deleted`.
- **MCP server:**
  - `ApiClient` is built with the service key and sends `X-Goalner-Service-Key` with every API request;
  - `TokenVerifier` and `ToolCall` read the code of a 401, as `ConnectionTokens` does.
- **API document:** the `assigned` view and the `agent` and `deleted` fields of users. MCP tools follow it.
- **Web client:**
  - `ProjectAgentsPage.vue` and its dialogs;
  - an agent marker on avatars;
  - a project navigation entry;
  - i18n (`en`, `ru`).
- **Deployment:** a null MX record (`agents.goalner.com. MX 0 .`). `MCP_SERVICE_KEY` is now also sent by the MCP server on every API request and checked by the API. No new secret is needed.
- **Depends on:** `add-mcp-oauth` and `harden-mcp-oauth`, which must be archived before this change is archived.
  - **Code:** theirs is already on main, so implementation does not wait. It provides `api_tokens.project_id` nullable, `MCP_SERVICE_KEY`, and the rule that a refused service key is not reported as a dead token.
  - **Specs:** their deltas restrict the one-project token rules to personal tokens, and the `web-client` delta here is written on top of theirs.
