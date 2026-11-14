## 1. Prerequisites

- [x] 1.1 Confirm the code of `add-mcp-oauth` and `harden-mcp-oauth` is on main:
  - `db/schema.rb` shows `api_tokens.project_id` nullable and the check constraint `api_tokens_project_or_connection`;
  - `MCP_SERVICE_KEY` is in `RequiredSecrets` and read as `Rails.configuration.x.oauth.service_key`;
  - `ConnectionTokens#exchange` keys on the code of a 401;
  - `config.x.domain` is set.

## 2. Agent accounts

- [x] 2.1 Add the `agents` migration (`user_id` unique foreign key, `created_by_id` foreign key to `users`, `deleted_at`, timestamps). Verify that `bin/rails db:migrate` succeeds and `db/schema.rb` shows the table, its unique index and both foreign keys.
- [x] 2.2 Add `Agent` (`belongs_to :user`, `belongs_to :created_by`), and on `User`: `has_one :agent`, `#agent?`, `User.active`, and a validation that agents are never `admin`. Verify with model tests for `agent?`, `active` (deleted agents excluded, people kept) and the `admin` validation.
- [x] 2.3 Add `config.x.agents.email_domain` (`"agents.#{config.x.domain}"`) and `Agent::Handle`:
  - word lists of about 100 adjectives and 100 animals;
  - `<adjective>-<animal>-<nnnn>` on the agent domain;
  - up to 5 retries on `RecordNotUnique`.

  Add `Agent.create_in!(project, name:, created_by:)`, which creates the user (random unused password, `confirmed_at` now, `lang` `en`), the agent and the membership in one transaction. Verify with model tests for the format, a forced collision that retries, and the membership.
- [x] 2.4 Reject addresses on the agent domain for new people (`User`) and for `Invitation`. Verify with controller tests:
  - registering `x@agents.goalner.com` gives 422 on the email field with no account and no email;
  - inviting such an address gives 422 with no invitation and no email.

## 3. Sign-in guards and mail

- [x] 3.1 `SessionsController#create`: refuse agents with the generic error, and skip `register_failed_sign_in!` for them. Verify with controller tests: an agent's address gets the same error as an unknown one, and ten failures send no unlock email and leave the agent unlocked.
- [x] 3.2 Make `PasswordsController`, `ConfirmationsController`, `UnlocksController` and `RegistrationsController` answer for an agent's address as for an unknown one, without mail. Verify with one test per flow using `assert_no_enqueued_emails`.
- [x] 3.3 Add `AgentMailInterceptor`, registered in every environment. It strips recipients on the agent domain and drops the message when none remain, logging only the mailer name. Verify with mailer tests: a message to an agent is not delivered, and a message to a person and an agent reaches only the person.
- [x] 3.4 `TaskAssignment.notify` returns early for agent assignees. Verify with tests: assigning to an agent sends nothing, and an agent assigning a person sends one email naming the agent.

## 4. Agent tokens

- [x] 4.1 Migrate `api_tokens`: add `issuer_id` (foreign key to `users`) and `channels`, make `expires_at` nullable, and replace `api_tokens_project_or_connection` with the three-kind `api_tokens_kind` (design decision 5). Verify that the migration runs and rolls back, and that a model test shows the database rejects a row mixing kinds.
- [x] 4.2 `ApiToken`:
  - `personal` and `personal?` also require no issuer;
  - `of_agents` scope and `agent?`;
  - `issuer` association;
  - `channels` enum (`api`, `mcp`, `api_mcp`);
  - `active` including `expires_at IS NULL`;
  - at most 20 live tokens per agent.

  Add `Agent#tokens`. Verify with model tests, including that agent tokens are absent from `personal` and from `User#api_tokens`, and do not count toward the issuer's 20.
- [x] 4.3 `Current#projects` for agent tokens: the agent's kept projects that the issuer is also a member of. Verify with request tests for every scenario of the spec requirement "Agent token reach", including that an empty reach authenticates with an empty project list.
- [x] 4.4 `ApiTokenAuthentication`, for agent tokens issued for a single channel (design decision 7):
  - no `X-Goalner-Service-Key` is the API channel, and the configured key (`secure_compare`) is the MCP channel;
  - any other key answers 401 `invalid_service_key`;
  - the wrong channel answers 401 `invalid_token`.

  Verify with request tests:
  - an MCP-only token used directly gets 401 `invalid_token`;
  - a forged key gets 401 `invalid_service_key`;
  - an API-only token with the real key gets 401 `invalid_token`;
  - a token with both channels works directly, with the real key and with a wrong key;
  - the key without a token gets 401;
  - personal tokens are unaffected by a wrong key.
- [x] 4.5 Add the service key header to the header deny-list in `config/initializers/sentry.rb`. Verify with a test of the scrubber, and extend `test/integration/log_filtering_test.rb` to assert that a request carrying the key does not log its value.

## 5. Agent management API

- [x] 5.1 Add `Agent.visible_to(user)`: agents with a membership in the user's kept projects, deleted ones included. Verify with model tests: visible through a shared kept project, not through an archived one, deleted agents included.
- [x] 5.2 Add the session-only routes and controllers of design decision 4:
  - `Api::AgentsController`;
  - `Api::Agents::RestorationsController`;
  - `Api::Agents::TokensController`;
  - `Api::Projects::AgentsController`;
  - `Api::Projects::AgentMembershipsController`.

  Use password re-entry and a shared limit of 10 an hour for creation and issuing. Verify with request tests covering the `agents` spec scenarios:
  - creation, a wrong password counting toward lockout, and 404 for an archived project;
  - 404 for outsiders and 403 for any token;
  - the limit of 20 tokens per agent and the hourly 429;
  - the list showing the issuer and last four characters, and revoking a token another user issued;
  - adding an agent to another project, and 404 for a project the user does not belong to.
- [x] 5.3 `Agent#delete!` and `#restore!` (design decision 8). Verify with tests:
  - delete removes all tokens, unassigns open tasks across projects, keeps done tasks' assignee and lists the agent among the deleted;
  - a member of a project the deleter is not in can see and restore it;
  - restoring brings back no tokens or assignments, and old tokens stay 401.
- [x] 5.4 `Api::Projects::MembersController#destroy`: owner only for people, any member for agents, and 422 when the project is the agent's last kept project. Verify with request tests for each case and that the agent's tasks in the project are unassigned.

## 6. Tracker integration

- [x] 6.1 Apply `User.active` in the member list, `User#teammates` and `Task#assignee_is_member`. Verify with tests:
  - a deleted agent is not listed or a teammate;
  - assigning it gives 422;
  - its statistics overview gives 404;
  - active agents are listed and assignable.
- [x] 6.2 Add `agent` and `deleted` to `UserSerializer#card`, and preload `:agent` wherever cards are rendered (board, task detail, comments, members, teammates). Verify with serializer tests for the fields, and a query-count test showing that board rendering does not grow with the number of assignees.
- [x] 6.3 Add the `assigned` view to `Api::Projects::TasksController#index`. Verify with request tests for the scenarios "An agent's work" (order, done and others' tasks excluded, subtask parent) and "Backlog and sprint".
- [x] 6.4 Add an integration test for the scenarios of "Agents work like members". With agent tokens:
  - Fish creates a task assigned to Owl;
  - Fish comments with a token Bob issued;
  - Fish assigns Bob.

  Verify the creator, the author, the assignee and the email naming Fish.

## 7. API document and MCP server

- [x] 7.1 Document in `docs/openapi.yaml`:
  - the `assigned` value of the task list's `view`, with an example;
  - the `agent` and `deleted` fields of user objects.

  Verify that `bin/openapi-verify` passes.
- [x] 7.2 Build `GoalnerMcp::ApiClient` with the service key, so it sends `X-Goalner-Service-Key` on every API request. Verify with a test in `test/mcp` that the header is present on the `GET /api/me` verification and on a tool call.
- [x] 7.3 `TokenVerifier#verify` and `ToolCall#call` read the code of a 401: only `invalid_token` means a dead token, and any other 401 raises `ApiClient::Unavailable`. Verify with tests in `test/mcp`:
  - `createTask` with an MCP-only agent token creates a task whose creator is the agent;
  - listing tools with an API-only agent token gives 401 with `WWW-Authenticate: Bearer`;
  - with a service key the API refuses, listing tools with an MCP-only agent token gives 503 without `error="invalid_token"`, and a tool call after a successful list returns the "unavailable" tool error;
  - a personal token still lists tools, also with a refused service key.

## 8. Web client

- [x] 8.1 Add the `agent` and `deleted` fields of the user card, and agent and agent-token types, to `api/types.ts`. Add `api/agents.ts` for the new endpoints, with its list logic tested in `api/agents.test.ts`. Verify that `npm run typecheck` and `npm test` pass.
- [x] 8.2 Add the agent marker to `UserAvatar.vue`: an icon with a visually hidden "Agent" ("Агент"), plus a deleted state, without relying on colour. Verify on the board card, task page, comments and members page, with a system test asserting the accessible name.
- [x] 8.3 Show the marker in the assignee pickers and the dashboard's teammate choice. Deleted agents are not offered. Verify with a system test of the assignee picker scenario.
- [x] 8.4 Add `ProjectAgentsPage.vue`, its route and the project navigation entry (sidebar and collapsed rail), listing active agents and a collapsed group of deleted ones. Verify with a system test that every member sees the entry and the lists.
- [x] 8.5 Add the create-agent dialog: name, token name, access, channels and password. Reveal the value once with a copy control and a warning. For MCP, show the `claude mcp add` command and a JSON `mcpServers` block for `<origin>/mcp`, and a link to the MCP guide (`/docs/mcp`). For the API, show a link to the API documentation. Verify with system tests for "Create with MCP" and "Wrong password".
- [x] 8.6 Add: add an existing agent, rename, remove (hidden for the agent's last project, where delete is offered), delete with confirmation, and restore. Verify with system tests for "Only project" and "Restore".
- [x] 8.7 Add the tokens dialog: list with issuer, access, channels, last four characters, created and last use; issue with the same reveal as 8.5; revoke with confirmation. Verify with a system test that issues and revokes a token.
- [x] 8.8 Add all new strings in `en` and `ru`. Verify:
  - `npm run policy` passes;
  - the accessibility system test covers the Agents screen;
  - the client runs under the production CSP with no violations;
  - a keyboard-only pass through every new dialog works (focus kept inside, Escape closes, focus returns).

## 9. Deployment and documentation

- [ ] 9.1 Publish `agents.goalner.com. MX 0 .`. Verify that `dig +short MX agents.goalner.com` prints `0 .`.
- [x] 9.2 Add an "Agents" section to the README: what an agent is, channels, and configuring an MCP client with an agent token. Review it in the rendered README.
- [ ] 9.3 Test end to end in development:
  1. Create an agent in the web client with an MCP token, and add it with `claude mcp add`.
  2. Assign it a task.
  3. Through MCP, list its assigned tasks, move the task and comment.

  Verify that the board shows the agent as the actor, and that `bin/ci` passes.
- [ ] 9.4 Before archiving this change, confirm that `add-mcp-oauth` and `harden-mcp-oauth` are archived (`openspec list --json` no longer lists them), and that `openspec validate add-agents --strict` still passes.
