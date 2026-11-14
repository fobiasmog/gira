# Notes

## Implementation (2026-11-14)

34 of 37 tasks are done. The three left need a person or another change:

- **9.1** Publish the null MX record for `agents.goalner.com`. Not done: it is a DNS change outside the repository.
- **9.3** The manual check with the web client and `claude mcp add`. The scripted equivalent below passes. `bin/ci` does not pass, for a reason outside this change (see "Found along the way").
- **9.4** Before archiving: `add-mcp-oauth` and `harden-mcp-oauth` must be archived first.

### Checks that pass

| Check | Result |
|---|---|
| `bin/rails test` | 791 runs, 0 failures |
| `bin/openapi-verify` | 63 runs, 0 failures |
| `bin/rubocop`, `bin/brakeman` | no offenses, no warnings |
| `npm run typecheck`, `npm test`, `npm run policy` | pass (102 frontend tests) |
| `test/system/agents_test.rb`, `accessibility_test.rb` | 17 runs, 0 failures |
| `openspec validate add-agents --strict` | valid |

### The flow over real HTTP

Rails (`RAILS_ENV=test bin/rails server -p 3011`, fixtures loaded) and `bin/mcp` (`MCP_PORT=3111`, `GOALNER_API_URL=http://localhost:3011`), driven by a script with no browser. two is a member of GOAL.

| Step | Result |
|---|---|
| two signs in and creates agent "Fish" with an MCP-only, read-write token | 201, `modest-gazelle-0519@agents.goalner.com`, `agent: true` |
| two creates GOAL-1 assigned to Fish | 201, in To Do, assignee Fish |
| `tools/list` at `/mcp` with Fish's token | 200, 35 tools |
| `listTasks` with `view: assigned` | GOAL-1 |
| `placeTask` to Work, `createComment` "On it." | both succeed; the comment's author is Fish, `agent: true` |
| `createTask` as Fish | GOAL-2, creator Fish |
| two reads GOAL-1 | in Work, with Fish's comment |
| The MCP-only token sent directly to `/api/me` | 401 `invalid_token` |
| The same with a made-up service key | 401 `invalid_service_key` |
| Fish's token on `POST /api/projects/:id/agents` | 403 `token_not_allowed` |
| two deletes an agent, then a tool call with its token | 401 `invalid_token`, and `tools/list` is 401 after it |
| two restores it | no tokens, and the old token still gets 401 |

`tools/list` alone keeps answering 200 for up to a minute after a token dies, until a tool call is refused: the MCP server remembers a verified token for 60 seconds (`TokenVerifier::TTL`), as it does for personal tokens. Listing tools returns no project data.

### Deviations from the plan

- **`User.active`** is `where.not(id: Agent.deleted.select(:user_id))`, not a left join, so it composes with other joins. design.md is updated.
- **The board snapshot** also renders the member list, which design.md's list of call sites missed. Both use `Project#listed_members` now.
- **The check constraint** spells out `channels IS NOT NULL`. A CHECK passes when its expression is NULL, and `NULL IN (...)` is NULL, so the first version accepted an agent token without channels. A model test caught it.
- **The comment list** loaded each author's avatar with two queries. It now preloads them: more agents means more distinct authors.
- **Agent ids.** The API uses the agent's account id everywhere, the one member lists and `assignee_id` carry. `agents.id` stays internal.
- **Creation response.** The first token is under `first_token`, and its errors are named `token.name`, `token.access` and `token.channels`, so they cannot be confused with the agent's own name.
- **Issuing a token for a deleted agent** is a validation error, not a 404: the member can see the agent, and the message says to restore it.
- **The Team screen** links agents to the Agents screen instead of offering the owner's remove button.
- **The MCP URL in the token reveal** (found in the first manual use, 2026-11-14). The snippets were built from `location.origin + "/mcp"`. In development the page is on port 5173 and the MCP server on 3100, so the copied `claude mcp add` command connected to nothing. The response that issues a token now carries `mcp_url` (`Oauth.resource`), and the snippets use it. The Connected apps screen of `add-mcp-oauth` still uses the origin and is wrong in development in the same way; not changed here.

### Found along the way, not changed

- **`bin/ci` fails at the gem audit.** Four advisories against `rack 3.2.7`, fixed in 3.2.8. `Gemfile.lock` is untouched by this change.
- **Two system tests fail on this machine** and pass on Linux in UTC:
  - `DashboardTest#test_deadlines_show_date_tiles_with_today_highlighted` builds "due today" from UTC's end of day, which is tomorrow in CET. It passes with `TZ=UTC`.
  - `TaskPageTest#test_post_a_comment_with_an_attachment,_edit_it_and_delete_it` selects all with Ctrl+A, which macOS does not do. It passes with Cmd+A.
- **The MCP server's instructions** (`GoalnerMcp::INSTRUCTIONS`) do not mention the `assigned` view. One sentence there would tell agents where to find their work. Not in this change's tasks.
