# Design

## Context

- **`add-mcp-oauth` and `harden-mcp-oauth` are on main** (not yet archived). They provide:
  - **Schema:** `api_tokens.project_id` nullable, with the check constraint `api_tokens_project_or_connection` (exactly one of `project_id` and `oauth_access_token_id`).
  - **Token kinds:** `ApiToken.personal` is `where(oauth_access_token_id: nil)`, and `of_connections` drops that condition. `User#api_tokens` is personal tokens only.
  - **Reach:** `Current#projects` narrows personal tokens to their project and gives connection tokens every project.
  - **Service key:** `MCP_SERVICE_KEY` is read as `Rails.configuration.x.oauth.service_key` and by `bin/mcp`. Only `ConnectionTokens` sends it, as `X-Goalner-Service-Key`, to the exchange.
  - **Refused service key:** the MCP server keys on the error code of a 401. Only `invalid_token` means a dead token, and anything else answers 503 (`harden-mcp-oauth` design.md, decision 3).
  - **Domain:** `config.x.domain` is `goalner.com`.
  - **Specs:** the token spec text that limits the one-project rules to personal tokens.
- **Actors in the data are users.** Every column that records who did something points at `users`: `tasks.creator_id`, `tasks.assignee_id`, `comments.author_id`, `memberships.user_id` and `api_tokens.user_id`. `Task#assignee_is_member` accepts any member. Changes made with a token are attributed to `api_tokens.user_id`.
- **Email reaches an account from signed-out flows.** `PasswordsController#create`, `RegistrationsController#create` (`attempted_registration`) and the lockout in `User#register_failed_sign_in!` (`unlock`) all send mail to an account's address on a stranger's request.
- **How MCP calls reach the API.** The MCP server calls the API over the private network (`GOALNER_API_URL`), not through nginx. It verifies a `glnr_` token with `GET /api/me` and forwards it on every tool call. The API cannot tell these requests from direct ones today.
- **Membership changes.**
  - `Project#remove_member!` unassigns the member's tasks and deletes the project's tokens that belong to that member, matched by `project_id`.
  - Only the project owner may remove members (`Api::Projects::MembersController`).
- Decisions made while exploring are recorded in proposal.md and the specs. This document covers how they are built.

## Goals / Non-Goals

**Goals:**
- **An agent is just another user wherever work is recorded.** Assignment, attribution, the board, comments and statistics need no special cases for agents.
- **A token never reaches a project its issuer cannot.** This holds even though agents are shared by all members of their projects.
- **No email ever leaves for an agent address.** This must not depend on DNS alone, and must survive mailers added later.
- **The API stays the only enforcer.** Agent tokens go through the same authentication, allowlist, access check and rate limit as every other token.

**Non-Goals:**
- **No runtime state.** There is no polling, queue or webhook, and no runtime configuration on agents yet. The `agents` table is where runtime configuration will go later.
- **No generic channel restriction.** Personal and connection tokens keep working on both channels.
- **No soft deletion of users.** Agents carry `deleted_at`, not `users`.

## Decisions

### 1. An agent is a `users` row with an `agents` row beside it

**Schema.** `agents` has:
- `user_id` (unique, foreign key, not null);
- `created_by_id` (foreign key to `users`, not null);
- `deleted_at`;
- timestamps.

**Models:**
- `User has_one :agent`, and `User#agent?` is `agent.present?`.
- The `agents` row is the only source of "is an agent". Authorization never looks at the email domain.

**What follows for free.** Membership, assignee validation, `creator_id`, `author_id`, `api_tokens.user_id`, statistics and teammates all keep working, because an agent is a user.

**Rules on agent rows:**
- `admin` stays `false` (a model validation);
- `confirmed_at` is set at creation, so nothing treats the agent as a half-registered account;
- `lang` is `en`;
- the default avatar is attached as for everyone.

Alternatives:
- *A separate `agents` actor table with polymorphic `assignee`, `creator` and `author` columns.* Rejected. It touches every query, serializer and screen that shows a person, loses the foreign keys, and changes the API document's user shape everywhere.
- *A human assignee plus an agent "delegate" column.* Rejected. It needs a twin column for every actor field, and agents create tasks and comments too.
- *Agent columns directly on `users`.* Workable today. The side table keeps agent-only behaviour (handles, deletion, and runtime configuration later) out of the authentication-heavy `User`.

### 2. Addresses and the reserved domain

**Domain.** `config.x.agents.email_domain = "agents.#{config.x.domain}"` in `config/application.rb`, which is `agents.goalner.com`. `Agent.email_domain` reads it. Production DNS publishes `agents.goalner.com. MX 0 .` (RFC 7505), and nothing else is needed for the name.

**Handle generation.** `Agent::Handle.generate` builds `"#{adjective}-#{animal}-#{'%04d' % rand(10_000)}"` from two frozen word lists of about 100 entries each. That gives about 10^8 combinations. It inserts with the unique index on `users.email_address` and retries up to 5 times on `ActiveRecord::RecordNotUnique`.

**The domain is checked in only two places,** both of them refusals:
- `User` validates that a new person's address is not on the agent domain, which covers registration;
- `Invitation` validates the same.

Neither reveals whether an agent has the address, because both refuse the whole domain.

### 3. Agents cannot authenticate, and mail to them is dropped twice

**No known password.** Agents get `password = SecureRandom.base58(64)`, which is never stored or shown. `has_secure_password` keeps `password_digest NOT NULL`.

**Explicit guards** answer as for an unknown address:
- `SessionsController#create`: a verified agent is refused like a wrong password, and `register_failed_sign_in!` is skipped for agents, so no lock and no unlock mail;
- `PasswordsController#create`;
- `ConfirmationsController#create`;
- `UnlocksController#create`;
- `RegistrationsController#create`: `attempted_registration` is never sent to an agent. Registration on the domain is already refused by decision 2.

**Mail, two layers:**
- `TaskAssignment.notify` returns early when the assignee is an agent;
- an `ActionMailer` interceptor (`AgentMailInterceptor`) removes every recipient on the agent domain. It drops the message when none remain, and logs only the mailer name. It catches mailers written later.

**DNS** is the third, external layer.

### 4. Who sees an agent: one scope, checked on every agent request

`Agent.visible_to(user)` returns agents with a membership in `user.projects.kept`. It includes deleted agents, because their memberships are kept (decision 8). Every agent endpoint looks the agent up through this scope, so anything outside it is a 404.

**No endpoint is opened to tokens** (none uses `allow_token_access`). Agents, and tokens in general, get 403 from the existing allowlist.

**Routes** (session only):

| Route | Purpose |
|---|---|
| `GET /api/agents` | active agents the user can see, with the projects they share (the "add existing" picker) |
| `PATCH /api/agents/:id` | rename |
| `DELETE /api/agents/:id` | soft delete |
| `POST /api/agents/:id/restoration` | restore |
| `GET /api/agents/:agent_id/tokens` | list tokens |
| `POST /api/agents/:agent_id/tokens` | issue a token (`name`, `access`, `channels`, `current_password`) |
| `DELETE /api/agents/:agent_id/tokens/:id` | revoke a token |
| `GET /api/projects/:project_id/agents` | the project's agents, active and deleted |
| `POST /api/projects/:project_id/agents` | create (`name`, `token: { name, access, channels }`, `current_password`) |
| `POST /api/projects/:project_id/agent_memberships` | add an agent from `visible_to` to this project (`agent_id`) |
| `DELETE /api/projects/:project_id/members/:id` | remove (existing route, extended in decision 9) |

Password re-entry reuses `PasswordReentry` and `User#verify_reentered_password`, so lockout counting is shared with personal tokens.

**Rate limit.** `rate_limit to: 10, within: 1.hour, by: Current.user.id` covers both agent creation and token issuing (one `scope:`).

### 5. Agent tokens are `api_tokens` rows

**Schema:**
- `issuer_id`: foreign key to `users`, null for other kinds;
- `channels`: string `api`, `mcp` or `api_mcp`, null for other kinds;
- `expires_at` stays NOT NULL, for every kind.

**Expiry.** An agent token is issued for `ApiToken::AGENT_LIFETIME`, 100 years. A `before_create` sets it, whatever was given, so the issuer cannot choose another lifetime. In practice the token does not expire, and still every token has an expiry date: the `active` and `expired` scopes, the purge job and anything written later never meet a token without one. The first version made `expires_at` nullable for agent tokens. That was dropped on review (2026-11-16), because every reader of the column would have had to remember the null case.

**Check constraint.** `api_tokens_project_or_connection` is replaced by `api_tokens_kind`, which allows exactly one kind:
- personal: `project_id` set;
- connection: `oauth_access_token_id` set;
- agent: `issuer_id` and `channels` set, `project_id` and `oauth_access_token_id` null.

It says nothing about `expires_at`, which the column's NOT NULL covers.

**`ApiToken`:**
- `personal` becomes `where(oauth_access_token_id: nil, issuer_id: nil)`, and `personal?` also requires no issuer. Without this, an agent token would count as personal: it would need a project and an expiry, and `Current#projects` would give it none;
- `scope :of_agents`, which drops the `personal` conditions as `of_connections` does, and `agent?`;
- `belongs_to :issuer, class_name: "User", optional: true`;
- `channels`: an enum over `api`, `mcp` and `api_mcp`, validated for agent tokens only;
- `active` is unchanged, `where(expires_at: Time.current..)`, and `find_active_by_value` keeps its join;
- the 20-live-tokens validation is per agent (`user_id`), on create.

**Why this kind of row.** The token's `user_id` is the agent, so attribution, `touch_last_used!`, the per-token rate limit, the endpoint allowlist and the read-only check work unchanged. `Current.user` is the agent.

**The agent's tokens** are `ApiToken.of_agents.where(user_id: agent.user_id)` (`Agent#tokens`). `User#api_tokens` holds personal tokens only, so it is empty for an agent.

**Deleting an agent** runs `agent.tokens.delete_all`. Rows are gone, so tokens never come back (spec: "SHALL NOT work again").

Alternatives:
- *An `agent_tokens` table.* Rejected. It would duplicate `ApiTokenAuthentication` and every rule that hangs off it.
- *Tokens owned by the issuer, with an "acts as" column.* Rejected. Attribution and `Current.user` would have to be special-cased in every controller.

### 6. Reach: the agent's projects that the issuer also belongs to, at request time

`Current#projects` for an agent token:

```ruby
user.projects.kept.where(id: api_token.issuer.projects.kept.select(:id))
```

Here `user` is the agent. One query, evaluated per request, so:
- membership changes on either side take effect on the next request without any hook;
- `Project#archive!` needs no change, and `#remove_member!` needs none for reach. Agent tokens have no `project_id`, so its `api_tokens.where(user:)` deletion skips them.

**Empty reach.** A token whose issuer shares no project with the agent any more still authenticates and sees nothing. It stays in the agent's token list, where the issuer is shown and any member can revoke it.

Alternatives:
- *One project per token.* The user chose one token for all of the agent's projects.
- *The agent's projects regardless of issuer.* Rejected. A member of OPS only could issue a token for an agent that is also in GOAL, and read GOAL with it.
- *Delete tokens whose reach becomes empty.* Deferred. It needs hooks on leave, removal and archive, and the list already exposes such tokens. It can be added later without a spec change other than its scenario.

### 7. Channels: the MCP server labels its requests with its service key

**MCP side.** `ApiClient.new(transport, service_key:)` adds `X-Goalner-Service-Key` to every API request, including the `GET /api/me` verification. `ConnectionTokens` keeps passing the same header to the exchange.

**API side.** `ApiTokenAuthentication#authenticate_by_api_token` reads the header only for an agent token issued for a single channel:

| `X-Goalner-Service-Key` | Channel | Answer when the token's channel differs |
|---|---|---|
| absent | `:api` | 401 `invalid_token` |
| equals `Rails.configuration.x.oauth.service_key` (`secure_compare`) | `:mcp` | 401 `invalid_token` |
| anything else | none | 401 `invalid_service_key`, whatever the token's channel |

Personal tokens, connection tokens and agent tokens issued for both channels never read the header.

**The MCP server reads the code of a 401,** in `TokenVerifier#verify` and `ToolCall#call`, as `ConnectionTokens#exchange` does:
- `invalid_token`: the token is dead, as today;
- any other 401: logged as "the API refused the MCP server's credentials; check MCP_SERVICE_KEY", and raised as `ApiClient::Unavailable`. `Authentication` answers 503, and a tool call returns the "unavailable" tool error.

**Through MCP.** An API-only token fails `GET /api/me` with 401 `invalid_token`, so the MCP server answers 401.

**Why 401 `invalid_token`, not 403, on the wrong channel.** There the token does not exist. The MCP server already maps it to an HTTP 401, and the response tells a direct caller nothing beyond "invalid".

**The key alone opens nothing.** It only labels a request that a token authenticates. The `add-mcp-oauth` goal "the MCP process gains no power of its own" holds.

**Hygiene:**
- `config/initializers/sentry.rb` keeps request headers except a deny-list, which gains the service key header;
- the MCP server already drops every header from its reports;
- Rails does not log request headers, which `test/integration/log_filtering_test.rb` asserts for the key.

Alternatives:
- *A wrong or missing key counts as a direct request.* Rejected. With a misconfigured or rotating key, an MCP-only token would get 401 `invalid_token` with an OAuth challenge, which `harden-mcp-oauth` fixed for connections.
- *Refuse a wrong key for every token.* Rejected. A key problem would also take down personal tokens through MCP, which do not depend on the key today.
- *Different token prefixes per channel (`glnr_mcp_`).* Rejected. The API still needs to know where a request came from to enforce it, and the prefix enforces nothing.
- *The MCP server exchanges agent tokens for short-lived ones (like connection tokens).* Rejected. It is the whole `add-mcp-oauth` exchange machinery, for a label.
- *nginx sets the header.* Not possible, because the MCP server reaches the API without passing nginx.

### 8. Soft delete keeps memberships and hides them

**Delete** (`Agent#delete!`, one transaction):
1. Set `agents.deleted_at`.
2. Delete all of the agent's tokens (`agent.tokens`, decision 5).
3. Unassign it from tasks that are not archived and not in a done column, in every project.

Memberships stay, and done and archived tasks keep it as assignee for history.

**Restore.** `Agent#restore!` clears `deleted_at`. Tokens and assignments are not restored.

**Hiding.** `User.active` is `where.not(id: Agent.deleted.select(:user_id))`. It is applied at the places that list or accept people:
- `Project#listed_members`, which the member list and the board snapshot both render;
- `User#teammates` (and so statistics, which 404 on non-teammates);
- `Task#assignee_is_member`, which refuses a deleted agent as "has been deleted";
- member removal, where a deleted agent is a 404;
- `GET /api/agents` (the add-existing picker lists active agents only).

**Serializers.** `UserSerializer#card` gains `agent` (boolean) and `deleted` (boolean, true only for deleted agents). Every place that renders many cards preloads `:agent` to avoid N+1 queries: the board, members, teammates, comments and the agent lists. The comment list also preloads its authors' avatars, which it loaded one by one before.

**One id per agent.** In the API an agent's id is its account's id, the one that member lists, `assignee_id` and comment authors carry. Agent routes look agents up by it, and `agents.id` stays internal.

**`Current#projects` needs no deleted-agent check.** Deleted agents have no tokens, so no request can authenticate as one.

Alternatives:
- *Remove memberships on delete.* Rejected. Nobody would share a project with the deleted agent, so nobody could see it to restore it.
- *Keep open assignments on delete.* Rejected. Open work would look owned while nobody works on it. Restore therefore brings no assignments back.

### 9. Removing an agent reuses `remove_member!`, with two rule changes

`Api::Projects::MembersController#destroy`:
- `require_owner!` applies only when the target is a person;
- for an agent, `Project#remove_member!` raises `Agent::LastProject` (rendered as 422) when the project is the agent's only kept project.

`remove_member!` already unassigns the agent's tasks in that project. The reach of the agent's tokens narrows through decision 6.

**When a person leaves or is removed,** tokens they issued narrow through decision 6, with no new code.

### 10. "Assigned to me" is a task-list view

`GET /api/projects/:project_id/tasks?view=assigned` is added to `VIEWS`. It returns:

```ruby
@project.tasks.kept.not_done.where(assignee: Current.user).joins(:status).order("statuses.position", :number)
```

It uses the card serializer, which already has `parent_id`. It is already open to tokens through `index`, and the API document gains the enum value. The MCP `listTasks` tool follows the document, so agents get it with no MCP change.

Alternative:
- *Open `/api/statistics/overview` to tokens.* Rejected. Cross-project data endpoints are closed to tokens on purpose (spec api-tokens), and the overview lists root tasks only, while agents delegate through subtasks.

### 11. Web client

**`ProjectAgentsPage.vue`,** a project section next to Members, lists the project's agents with an actions menu each, and its deleted agents in a collapsed group. It reloads the list after every change, so token counts and "can be removed" always come from the server. Its parts, in `components/agents/`:
- `AgentCreateDialog`: name, token name, access, channels and password. After creating, it shows the token until it is closed;
- `AgentAddDialog`: the user's visible agents that are not in the project yet;
- `AgentTokensDialog`: list, issue and revoke;
- `TokenFieldset`: the token's name, access and channels, shared by creating and issuing;
- `TokenReveal`: the value, shown once, with what its channels need.

Renaming, removing and deleting use `AppDialog` and `ConfirmDialog` on the page.

**MCP configuration.** For an MCP token, the reveal shows two snippets built from the MCP endpoint the server names in the response that issues the token (`mcp_url`, which is `Oauth.resource`, that is `MCP_RESOURCE_URL`), and a link to the MCP guide (`MCP_GUIDE_URL`, `/docs/mcp`). The page's own origin is not used: in development the application is on port 5173 and the MCP server on 3100, so `location.origin + "/mcp"` gave a command that connected to nothing. The Connected apps screen still builds its URL from the origin and has the same fault in development; that screen belongs to `add-mcp-oauth`.
- `claude mcp add --transport http goalner <mcp_url> --header "Authorization: Bearer <value>"`;
- a JSON `mcpServers` block.

**Checks.** The repository has no Vitest:
- `api/agents.ts` logic is tested with `node --test` (`npm test`);
- pages are tested by system tests and the accessibility test;
- `npm run typecheck` and `npm run policy` must pass.

**Agent marker.** Two parts, so the marker is visible and also named in words:
- **On avatars:** `UserAvatar` adds a robot badge for an agent, and a dashed, faded avatar for a deleted one. Every avatar renders through `UserAvatar`, so this covers cards, pickers, comments and members. The badge is decorative, as avatars are.
- **In words:** `AgentChip` ("Agent" or "Deleted agent") stands next to a name shown as text, and `personName()` gives "Fish (agent)" where there is only text: picker choices, the dashboard's teammate choice, tooltips and the hidden "Assigned to" text of cards.

The robot icon is drawn for Goalner and added to the sprite, which otherwise holds Material Symbols.

**Pickers.** Assignee pickers already read the project member list, which no longer contains deleted agents.

**Team screen.** An agent is listed with its chip and a link to the Agents screen in place of the owner's remove button: agents are handled there, by any member.

## Risks / Trade-offs

- **[A code path treats an agent as a person: a new mailer, admin tooling, the welcome announcement]** → The mail interceptor catches mail by domain, whatever the code path. The auth guards come with per-flow tests. `admin` is always false for agents. The welcome announcement is harmless, because agents never read announcements.
- **[Agent tokens are valid for 100 years, so a leaked one lives until someone acts]** →
  - every member sees issuer and last use, and any member can revoke;
  - deleting the agent kills all its tokens;
  - reach shrinks automatically as the issuer's memberships change.
- **[Any member can delete an agent that other projects rely on]** → Deletion is soft, and members of any of its projects can restore it. Finer permissions are a later change.
- **[Agents create tasks for agents in a loop]** →
  - the per-token limit of 300 requests a minute applies;
  - agents cannot create agents or tokens;
  - budgets belong to the runtime change.
- **[An agent's runtime carries information from one project to another]** → This is the same as a person in two projects, and Goalner cannot enforce against it. Reach is bounded by the issuer, so a runtime only ever holds keys to the projects its issuer belongs to.
- **[Kept memberships of deleted agents leak into a query that uses `project.members` directly]** → `User.active` is applied at the listed call sites. A test per call site asserts that deleted agents are absent. New code that lists or accepts members should use `members.active`.
- **[Handle collisions]** → With about 10^8 combinations and 5 retries, an exhausted retry raises and the creation answers 500. This is acceptable at this scale and visible in error tracking.
- **[Rotating or misconfiguring `MCP_SERVICE_KEY`]** → Until both roles hold the same key, agent tokens limited to one channel get 503 through MCP, and "unavailable" tool errors. Personal tokens and agent tokens for both channels are unaffected, and no client is told its token is invalid.
- **[Overlap with `add-mcp-oauth` and `harden-mcp-oauth`]** → This change depends on both (proposal). Schema, `Current#projects`, the service key and the 401 codes are built on top of them, not beside them.

## Migration Plan

1. **DNS:** publish `agents.goalner.com. MX 0 .` before release.
2. **Migrations:**
   - create `agents`;
   - add `api_tokens.issuer_id` and `api_tokens.channels`;
   - replace `api_tokens_project_or_connection` with `api_tokens_kind`.

   All of them are reversible while no agent rows exist.
3. **Deploy the MCP server and the application in either order.** The header is ignored by an application that does not check it, and no agent tokens exist before the application ships.
4. **Rollback.** Reverting the application leaves agent rows inert:
   - agent tokens still authenticate as the agent's account, since they have an expiry, but reach no project: the old `Current#projects` narrows every token without a connection to its `project_id`, which is null. To stop them entirely, roll the migration back, which deletes them;
   - agents cannot sign in;
   - cards render agents as ordinary users until re-deploy.
