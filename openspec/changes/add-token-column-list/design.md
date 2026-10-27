# Design

## Context

See proposal.md for the motivation and specs/ for the behavior. The current state that shapes the approach:

- **Columns are `Status` records**, managed by `Api::Projects::StatusesController` (`create`, `update`, `destroy`). Each action answers with the project's full column list. None of them is opened to tokens.
- **The board snapshot already returns the columns.** `Api::Projects::BoardsController#show` and `StatusesController#columns` both build them inline with `status.slice(:id, :title, :color, :position, :done)`. `docs/openapi.yaml` describes that shape as the `Column` schema, used by `Board.columns`.
- **Token access is opened per action** with `allow_token_access`, and `OPENED_TO_TOKENS` in `test/integration/api_token_authentication_test.rb` snapshots the full list. `bin/openapi-verify` fails when an opened action has no documented operation or no example.
- **`add-personal-api-tokens`, decision 4,** kept columns session-only because they are the board's structure and tokens do no administration.

## Goals / Non-Goals

**Goals:**
- Tokens can read a project's columns without loading the board's tasks.
- The column list and the board snapshot cannot drift apart in shape.

**Non-Goals:**
- Changing columns with a token. Decision 4 of `add-personal-api-tokens` stands.
- Moving the web client off the board snapshot for its columns.

## Decisions

### 1. An `index` action on the existing controller, opened alone

`resources :statuses` gains `index`, and `StatusesController` declares `allow_token_access only: :index`. `create`, `update` and `destroy` keep refusing tokens with 403 `token_not_allowed`. `index` uses `ProjectScoped` like the other actions, so a project outside the token's reach, an archived one or one the user does not belong to answers 404. The action needs no `set_status`.

*Alternatives:*
- *A separate read-only controller.* Rejected. Token access is already opened per action, and one resource is easier to follow in one controller.
- *Opening the column changes as well.* Considered and rejected while exploring this change: tokens stay read-only for the board's structure.

### 2. The path stays `/statuses`; the documentation says "columns"

The route is `GET /api/projects/{project_id}/statuses`, the same resource as the existing column routes, and the id it returns is the `status_id` that `placeTask` takes. The OpenAPI operation is `listColumns` and the schema stays `Column`, as the document already calls them.

*Alternative: a `/columns` alias.* Rejected. Two paths for one resource, and the only one that tokens could use would not match the routes the web client calls.

### 3. One column shape

The `slice(:id, :title, :color, :position, :done)` moves into one helper, used by the board snapshot, the column list and the column change responses. A small serializer next to the existing ones fits the codebase (`TaskSerializer.cards`, `UserSerializer#card`). The JSON stays exactly as it is today, so the web client and `Column` in the document are unaffected.

*Alternative: a third inline `slice`.* Rejected. The board and the list would then drift independently, and only the board would be checked by an example in `bin/openapi-verify`.

### 4. Documentation and verification

- **Operation:** `listColumns` under the `Projects` tag, beside `showBoard`. It returns an array of `Column` in board order, and its description says that the last column is the done column and that `id` is what `placeTask` takes as `status_id`.
- **Responses:** 200, 401 `Unauthorized`, 404 `NotFound` and 429 `RateLimited`. There is no 403 (read-only tokens are allowed) and no 422 (no input), as the api-documentation spec requires of a read operation.
- **Verification:** a `listColumns` example in `test/openapi/examples_contract.rb`. The parity test finds the route on its own, and `OPENED_TO_TOKENS` gains `api/projects/statuses#index`.

## Risks / Trade-offs

- [A new action widens what tokens can reach] → The data is already in the board snapshot, which every token can read. The snapshot test makes the new entry a reviewed change.
- [Session clients now have two ways to read columns] → The shared helper keeps them identical, and the `Column` schema checks both through `showBoard` and `listColumns`.

## Migration Plan

No data changes. The route is additive: deploying it changes no existing response. Rolling back removes the route and the action. Tokens then get the catch-all 404 for that path, and scripts fall back to the board snapshot.
