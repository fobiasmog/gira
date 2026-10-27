# Tasks

## 1. Viewer and endpoints (risk first)

- [x] 1.1 Add `swagger-ui-dist` at an exact version to `package.json` and `package-lock.json`. Extend `script/check-frontend-policy.mjs` so the package is allowed and required, and only `app/frontend/entrypoints/api-docs.ts` may import it (design.md, decision 6). Verify:
  - `npm ci --ignore-scripts`, `npm audit signatures` and `node script/check-frontend-policy.mjs` pass;
  - a temporary `import "swagger-ui-dist"` in an SPA module makes the policy check fail and name that file (spec web-client, "Documentation viewer imported by the application"). Remove the import afterwards.
- [x] 1.2 Add the two routes ahead of the API catch-all, plus `Api::OpenapiController` and `Api::DocsController` with the `api_docs` layout (design.md, decision 5). Also add:
  - the `api-docs.ts` entrypoint, its `.d.ts` file and the second Vite input (decisions 6 and 7);
  - a skeleton `docs/openapi.yaml`: info, `servers`, `bearerAuth`, the `Error` schema, and `GET /api/me` with its 200 and 401 responses;
  - an `api-docs.ts` entry in `test/fixtures/files/vite/manifest.json`.

  Verify request tests in `test/controllers/api/docs_controller_test.rb` and `test/controllers/api/openapi_controller_test.rb` for the api-documentation scenarios "Signed-in user opens the docs" (the page and its mount element), "Visitor without a session" (redirect, then back to `/api/docs` after sign-in), "Download the document" (YAML content type, 401 JSON when anonymous) and "Token request". Also verify:
  - `test/integration/api_token_authentication_test.rb` (route table and snapshot) and `test/integration/request_forgery_test.rb` still pass;
  - `npx vite build` emits both entrypoints in the manifest.
- [x] 1.3 Add `test/system/api_docs_test.rb`. With a production build, it covers:
  - the api-documentation scenario "No violations": open `/api/docs`, expand `GET /api/me`, authorize with a fixture token and execute. The production CSP header (via `ProductionProbe`) is unchanged, with no `securitypolicyviolation` events, only same-origin resources and no SEVERE console entries;
  - "Try without a token": a signed-in user executes `GET /api/me` without authorizing and sees 401;
  - "Token not kept": after authorizing and reloading, no token is entered and `localStorage` holds no `glnr_` value.

  If the policy reports violations, stop and bring the options in design.md (Risks) back to the user before writing any documentation.

## 2. Verification tooling

- [x] 2.1 Add `openapi_first` to the test group of the `Gemfile`, pinned in `Gemfile.lock`. Verify:
  - in the pinned version, `OpenapiFirst.load` reads the skeleton document;
  - `validate_request` and `validate_response` accept a Rack request built from an integration test's `request` and a Rack response built from its `response`, and raise with `raise_error: true`;
  - `bin/bundler-audit` passes.
- [x] 2.2 Add `test/openapi/support.rb` with `OpenapiContractTest` and its validation hook (design.md, decision 2). Verify `test/openapi/hook_contract.rb` against the skeleton document:
  - a conforming Bearer `GET /api/me` passes;
  - a response with a field missing from the schema fails, naming the operation and the field;
  - a response status the operation does not list fails, naming the operation and the status;
  - a Bearer request to an undocumented path fails, naming the method and path;
  - a non-conforming request that the API answers with 422 does not fail on the request.
- [x] 2.3 Add `bin/openapi-verify` (design.md, decision 8). Verify:
  - it exits 0 on the skeleton document, and exits non-zero naming the problem after the skeleton's `GET /api/me` response schema is temporarily broken;
  - it works from a fresh test database and with no server running;
  - the spec scenario "Default test run unaffected": `bin/rails test` reports the same number of runs before and after the `test/openapi/` files are added, and still passes with the broken skeleton;
  - `.github/workflows/ci.yml` and `bin/ci` are unchanged.

## 3. Document the token API

Each task documents its operations in `docs/openapi.yaml` (design.md, decision 1). It adds one entry per `operationId` to `EXAMPLES` in `test/openapi/examples_contract.rb` (decision 3), and verifies that `bin/openapi-verify` passes.

- [x] 3.1 Create `examples_contract.rb` and `parity_contract.rb`, starting with the document checks (decision 4). Add the shared components: the shared error responses and the `UserCard`, `Profile`, `Project`, `Column`, `Label`, `SprintSummary` and `Board` schemas. Document:
  - `GET /api/me`;
  - `GET /api/projects` and `GET /api/projects/{id}`;
  - `GET /api/projects/{project_id}/board` and `GET /api/projects/{project_id}/members`.

  Verify the api-documentation scenario "Session-only endpoint absent": a document check asserts there is no operation for project archiving, invitations or teammates.
- [x] 3.2 Document tasks:
  - `index` with its `view` values, `show`, `create`, `update` and `destroy`, including id-or-key paths;
  - subtasks (`index`, `create`), placement, completion (`update`, `destroy`), label (`update`, `destroy`) and sprint, with the `TaskCard`, `TaskDetail` and `Subtask` schemas.

  Verify:
  - the api-documentation scenarios "Opened endpoint documented" and "Read-only token writes", as document checks;
  - extend `test/system/api_docs_test.rb`, which runs in CI, with "Try with a token": create a task in GOAL from the page with a read-write token. The page shows 201, and the task's creator is the token's owner.
- [x] 3.3 Document comments (the task comments `index`, and `create` in JSON and multipart; `update` and `destroy` of a comment), labels, milestones with recovery, and sprints with activation, archival and sprint tasks. Add the `Comment`, `Attachment`, `Milestone`, `MilestoneDetail`, `Sprint` and `SprintTaskCard` schemas. Verify the api-documentation scenario "Validation errors" (the 422 of creating a label) as a document check. Verify that the multipart comment example uploads an attachment.
- [x] 3.4 Document `GET /files/{signed_id}` and `GET /files/{signed_id}/{variant}`: binary 200, bodiless 401 and 429, and the application's HTML 404 page. Verify the api-documentation scenario "File downloads" as a document check, with an example for each path.
- [x] 3.5 Add `test/openapi/errors_contract.rb`: one example per error kind, and the check that each operation lists the error responses it can give (design.md, decision 3). Verify it passes. Then confirm and revert:
  - removing the 403 response from a write operation fails the check, naming the operation ("Missing error response");
  - renaming `message` in the error envelope in `Api::BaseController#render_error` fails the 401 example, naming the response and the field ("Error envelope changed").
- [x] 3.6 Complete the parity checks: route-to-document parity, and `EXAMPLES.keys` against the document's operation ids (decisions 3 and 4). Verify `bin/openapi-verify` passes. Then, one at a time, confirm that the command exits non-zero with the stated message and revert:
  - an `allow_token_access` entry added to a session-only action names its method and path ("Endpoint opened without documentation");
  - a documented operation removed from `EXAMPLES` names it ("Operation without an example");
  - a field renamed in `TaskSerializer#card` names the operation and the field ("Response field renamed").

  Confirm that the document never fails `bin/rails test`. The suite still passes in the last two cases. In the first, only the existing api-tokens guards fail (the snapshot of opened actions, and the test that uses teammates as a session-only action), as designed.
- [x] 3.7 Time `bin/openapi-verify` on a warm test database and record the result in the pull request. If it takes more than 30 seconds, profile it before continuing (design.md, Risks).

## 4. Links and documentation

- [x] 4.1 Add the "API reference" link to the API tokens screen's intro (`en`/`ru`), and a link back to the API tokens settings in the docs page header (design.md, decision 9). Verify:
  - `test/system/api_tokens_test.rb` covers the web-client scenario "Link to the API documentation";
  - `npm test` (key parity), `npm run typecheck` and the policy check pass.
- [x] 4.2 Update the README's "API tokens" section to point to `/api/docs` and `/api/openapi.yaml` instead of `config/routes.rb`. Add a short "Verifying the API document" note: run `bin/openapi-verify` after touching a serializer, a token-opened action or `docs/openapi.yaml`, and it works as a `pre-push` hook. Verify:
  - on the dev server, using a signed-in session with `curl`, both URLs answer as the README says;
  - the documented command runs as written.

## 5. Integration

- [x] 5.1 Run the whole suite and the gates. Verify that all of these pass:
  - `bin/rails test` and `bin/rails test:system`, with a fresh `npx vite build --mode test`;
  - `npm test`, `npm run typecheck`, `npx vite build` and `node script/check-frontend-policy.mjs`;
  - `bin/brakeman`, `bin/bundler-audit` and `bin/rubocop`;
  - `bin/openapi-verify`, run separately, since it is not part of the suite;
  - `openspec validate add-openapi-docs --strict`.

  Confirm that the CI workflow does not run `bin/openapi-verify` or the `test/openapi/` files.
- [x] 5.2 On the dev server, in a browser:
  1. Create a read-write token in settings.
  2. Follow "API reference", authorize with the token, and create a task with "Try it out".
  3. Check that the task appears on the board.
  4. Check that a call without the token shows 401.
  5. Download `/api/openapi.yaml`.

## Workflow follow-up

- Release note: API documentation at `/api/docs` for signed-in users. The document is downloadable at `/api/openapi.yaml`.
- Add `bin/openapi-verify` to a git `pre-push` hook (the user, separately).
- Sync the delta specs and archive the change after review.
