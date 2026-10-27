# Proposal

## Why

Scripts that move tasks on the board need column ids for `placeTask`, but API tokens can only read columns inside the full board snapshot, which also carries the tasks, members and labels. There is no read route for columns at all, so the OpenAPI document has nothing to describe for them.

## What Changes

- A new route, `GET /api/projects/{project_id}/statuses`, lists the project's columns in board order. Each column has the same fields as in the board snapshot: id, title, color, position and whether it is the done column.
- The route is opened to API tokens, read-only and read-write alike. Members using the web client can call it too, but the web client keeps reading columns from the board snapshot.
- `docs/openapi.yaml` documents the route as `listColumns`, with its 200, 401, 404 and 429 responses, and `bin/openapi-verify` gets an example for it.
- The README's list of endpoints available to tokens includes the route. Its list of session-only endpoints says "changing columns" instead of "columns".

Not included:
- adding, renaming, moving or deleting columns with a token. Those stay session-only, as decided in `add-personal-api-tokens` (decision 4: no administration through tokens), and keep answering tokens with 403;
- changes to the responses or validation of the existing column routes;
- a single-column route (`GET .../statuses/{id}`) or task counts per column.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `project-board`: a new requirement, "List columns", lets members list a project's columns in board order.
- `api-tokens`: "Endpoints available to tokens" adds reading the project's columns. Changing columns still answers tokens with 403.

## Impact

- **Changed files:**
  - `config/routes.rb`: `index` joins `resources :statuses`;
  - `Api::Projects::StatusesController`: an `index` action, opened with `allow_token_access only: :index`;
  - `docs/openapi.yaml`: the `listColumns` operation, under the `Projects` tag;
  - `README.md`: the token endpoint lists.
- **Tests:**
  - a controller test for listing columns with a session and with tokens;
  - `OPENED_TO_TOKENS` in `test/integration/api_token_authentication_test.rb` gains `api/projects/statuses#index`;
  - a `listColumns` example in `test/openapi/examples_contract.rb`.
- **Existing behavior:** the board snapshot, the column change routes and the web client are unchanged.
