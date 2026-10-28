# Tasks

## 1. One column shape

- [x] 1.1 Move the column `slice(:id, :title, :color, :position, :done)` into one helper next to the existing serializers, and use it in `Api::Projects::BoardsController#show` and `Api::Projects::StatusesController#columns` (design.md, decision 3). Verify `test/controllers/api/projects/boards_controller_test.rb` and `test/controllers/api/projects/statuses_controller_test.rb` pass unchanged, with the same JSON as before.

## 2. Column list

- [x] 2.1 Add `index` to `resources :statuses` in `config/routes.rb`, and an `index` action to `StatusesController` that renders the project's columns in board order through the helper from 1.1. Open only that action with `allow_token_access only: :index` (design.md, decision 1). Verify in `statuses_controller_test.rb`, with a session, the project-board scenarios:
  - "List columns": the columns come back in order, and only the last one has `done: true`;
  - "Same columns as the board": the list equals the board snapshot's `columns`;
  - "Not a member": a non-member gets 404 with the JSON error envelope.
- [x] 2.2 Cover the api-tokens scenarios in `statuses_controller_test.rb` or `test/integration/api_token_authentication_test.rb`:
  - "Column list": `glnr_two_goal_read` lists GOAL's columns and gets 200;
  - "Columns of another project": the same token gets 404 for `projects(:side)`;
  - "Project administration": a read-write token still gets 403 `token_not_allowed` on create, update and destroy, and the columns do not change.

  Add `api/projects/statuses#index` to `OPENED_TO_TOKENS`, and verify `test/integration/api_token_authentication_test.rb` passes, including the route-table check.

## 3. Documentation

- [x] 3.1 Add the `listColumns` operation for `GET /api/projects/{project_id}/statuses` to `docs/openapi.yaml`, under the `Projects` tag after `showBoard`. It returns an array of `Column` and lists 200, 401 `Unauthorized`, 404 `NotFound` and 429 `RateLimited`. Its description says the last column is the done column and that `id` is what `placeTask` takes as `status_id` (design.md, decision 4). Add a `"listColumns"` example to `EXAMPLES` in `test/openapi/examples_contract.rb`. Verify `bin/openapi-verify` exits 0, and that it exits non-zero naming `listColumns` while the example is temporarily removed.
- [x] 3.2 In `README.md`, add `GET /projects/:id/statuses` to the endpoints available to tokens, and change "columns" to "changing columns" in the list of endpoints that answer tokens with 403. Verify the README lists match `OPENED_TO_TOKENS`.

## 4. Integration check

- [x] 4.1 Run `bin/rails test` and `bin/openapi-verify`, and check `/api/docs` shows `listColumns` under Projects for a signed-in user. Verify everything passes and the web client's board loads its columns as before.

## Workflow follow-up

- Archive the change once it is reviewed, syncing the `project-board` and `api-tokens` deltas into the main specs.
