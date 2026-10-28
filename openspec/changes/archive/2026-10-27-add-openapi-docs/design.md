# Design

## Context

See proposal.md for the motivation and specs/api-documentation/spec.md for the behavior. The current state that shapes the approach:

- **The token API is already enumerable.** Each controller declares its opened actions with `allow_token_access`, and `test/integration/api_token_authentication_test.rb` checks the full list against a snapshot (`OPENED_TO_TOKENS`, 36 `controller#action` pairs). `test/support/route_table.rb` walks the application's routes.
- **Response shapes live in hand-written serializers** (`app/serializers/*`, plus some inline JSON in controllers). `app/frontend/api/types.ts` mirrors them by hand for the SPA.
- **Tests are Minitest, run in parallel processes** (`parallelize(workers: :number_of_processors)`). There is no RSpec, so RSpec-based generators such as rswag do not fit.
- **The browser rules are strict:**
  - the production CSP allows scripts, styles and fonts only from `'self'`, and forbids inline scripts, injected `<style>` elements, `eval` and `new Function`;
  - pages load nothing from third-party origins (spec security-baseline);
  - frontend packages are on an allowlist enforced by `script/check-frontend-policy.mjs`, installed with `--ignore-scripts` and scanned by osv-scanner through `package-lock.json`.
- **Pages can load any Vite entrypoint.** `ViteHelper#vite_tags(entry)` already accepts an entrypoint name, but `vite.config.ts` builds only `application.ts`.
- **Every `/api/*` route answers a token with 403.** The route-table test sends a Bearer request to each `/api/*` route that is not opened and expects 403 `token_not_allowed` with the JSON envelope, so any new `/api/*` route must answer that way.

## Goals / Non-Goals

**Goals:**
- One command checks the whole document against the real API on demand, in both directions: routes against the document, and real responses against their schemas. It is quick enough for a git pre-push hook.
- The default test suite and CI never depend on the document, so an out-of-date document blocks nobody's CI run.
- Every check is deterministic under parallel test processes.
- The documentation page needs no exception to the CSP or to the third-party rule.

**Non-Goals:**
- Generating `types.ts` or client SDKs from the document.
- Accessibility work on Swagger UI's own markup. The SPA's accessibility test covers `#app` only, and the docs page is not part of the SPA.
- Changing any API response to make it easier to document. Inconsistencies found while writing the document are reported, not fixed here.

## Decisions

### 1. Hand-written OpenAPI 3.1 in one file

`docs/openapi.yaml` is written by hand, in one file.
- **Paths:** they include the `/api` prefix (and `/files/...` for downloads), with `servers: [{ url: "/" }]`, so a path in the document is exactly the request path.
- **Parameter names** match the Rails route parameters (`{project_id}`, `{task_id}`, `{id}`), so the parity check (decision 4) converts routes mechanically.
- **Grouping:** operations carry an `operationId` and a tag per resource: Profile, Projects, Tasks, Subtasks, Comments, Labels, Milestones, Sprints and Files.
- **Shared components:**
  - schemas named after `types.ts` (`TaskCard`, `TaskDetail`, `Comment`, `Sprint`, ...);
  - an `Error` schema for the envelope, with `code` as an enum;
  - shared responses `Unauthorized`, `InsufficientScope`, `NotFound`, `ValidationFailed` and `RateLimited`;
  - a `bearerAuth` security scheme applied globally.
- **Response objects** set `additionalProperties: false` and list every always-present field in `required`. A removed or renamed field fails the verification, and so does a new serializer field that is not documented. Nullable fields use `type: [..., "null"]`.
- **Request bodies stay open** (no `additionalProperties: false`), because Rails ignores unpermitted parameters.
- **Comment creation** documents both `application/json` and `multipart/form-data` (`body` plus `attachments[]` files).
- **Update actions:** Rails routes `update` to both PATCH and PUT, and the document lists one method per action. It uses PATCH for members of collections (`tasks/{id}`, `comments/{id}`), and PUT for singular sub-resources (placement, completion, label, sprint), matching what the web client sends.
- **Task paths:** `tasks/{id}` accepts a numeric id or a key such as `GOAL-12` (`find_by_ref!`). Task sub-resources accept the numeric id only. The document says so.

*Alternatives:*
- *Generate from controller annotations (oas_rails, rswag-style DSLs).* Rejected. rswag needs RSpec, oas_rails ships a viewer loaded from a CDN, and annotations drift as easily as YAML. Only checking against real responses keeps either form honest.
- *Split the document into files with `$ref`.* Deferred. About 34 operations fit in one file, and both the validator and the viewer can follow relative `$ref`s if it grows.

### 2. Validation with `openapi_first`, through our own hook

The `openapi_first` gem (test group, pinned in `Gemfile.lock`, audited by bundler-audit and osv-scanner) supplies the OpenAPI 3.1 and JSON Schema validation. We call its definition API (`OpenapiFirst.load`, then `validate_request` and `validate_response`) from a small hook. We do not use its Rack middleware or its exit-time coverage.

- **Where the hook sits:** in `OpenapiContractTest`, an `ActionDispatch::IntegrationTest` subclass in `test/openapi/support.rb`, which wraps `process` for that class only. After each request that carries `Authorization: Bearer`, the hook looks the request up in the document; a request that matches no documented operation fails the test, since every request in the contract suite is meant to be documented. The rest of the test suite never loads this class, so it runs exactly as before.
- **What it validates:**
  - the **response** always, including 401, 403, 404, 422 and 429, and failing on a status the operation does not list;
  - the **request** only when the response was 2xx, since the error examples deliberately send invalid input.
- **On mismatch** it raises with the operation, the status and the failing JSON pointer, which fails the running test.

*Alternatives:*
- *Prepend the hook to every integration test, so the ~40 existing token tests validate too.* Rejected. The verification stays out of the default suite and CI (proposal.md). A switch such as an environment variable would make the default suite run in two modes, and an unrelated failing test would then fail the schema check. The dedicated success and error examples (decision 3) cover the same ground.
- *`OpenapiFirst::Test.observe` with its coverage.* Rejected for coverage. It measures per process and enforces at exit, so each parallel worker would see a fraction of the requests and fail. It would also validate session requests to documented paths, which this change does not promise to keep in the token API's shape.
- *`committee`.* Rejected. Its OpenAPI 3.1 support is partial, and openapi_first supports 3.0 and 3.1.

### 3. Examples: one per operation, one per error kind

`test/openapi/examples_contract.rb` holds a table, `EXAMPLES`, keyed by `operationId`. Each entry is a small lambda that makes the documented success request with a fixture token. The class defines one test per entry, which asserts the documented success status, and the hook validates the response. A parity test asserts that `EXAMPLES.keys` equals the document's operation ids and names any missing or extra ids. That covers the spec scenario "Operation without an example".

`test/openapi/errors_contract.rb` covers the error side (spec api-documentation, "Error responses are verified"):
- **One example per error kind:**
  - 401 for an unknown token;
  - 403 `insufficient_scope` for a write with a read-only token;
  - 404 for another project of the owner;
  - 422 for creating a label with an empty title;
  - 429 for the 301st request in a minute;
  - the bodiless 401 and the HTML 404 page of a file download.

  The hook validates each of them against the operation it hits.
- **A check of the document itself:** every operation lists 401 and 429; every write operation lists 403; every operation with a path parameter lists 404; every operation with a request body lists 422. File downloads list their own 401, 404 and 429, since they answer without the JSON envelope. This catches the spec scenario "Missing error response" without needing an error example for each of the 34 operations.

This replaces runtime coverage measurement. It is deterministic, independent of the parallel workers, and gives a readable example per operation.

### 4. Route-to-document parity

`test/openapi/parity_contract.rb` derives the opened operations from the route table:
- take routes whose controller's `token_actions` includes the action, excluding `api/base#route_not_found`;
- strip `(.:format)`;
- expand optional segments, so `files/:signed_id(/:variant)` becomes two paths;
- turn `:name` into `{name}`;
- pair the method with the path, treating the PATCH and PUT of one update action as aliases.

It compares that set with the document's methods and paths and lists the differences both ways. Opening an action without documenting it fails the verification. The snapshot test that reviews the opened list stays in the default suite, unchanged.

The same file holds the document checks of the spec, such as "Session-only endpoint absent" and "Opened endpoint documented": a test that the document loads as valid OpenAPI 3.1, and assertions on individual operations.

### 5. Two endpoints, both refusing tokens with the JSON envelope

The routes `get "docs"` and `get "openapi.yaml", format: false` go inside `namespace :api`, ahead of the catch-all.

- **`Api::OpenapiController < Api::BaseController`, `show`** sends `docs/openapi.yaml` as `application/yaml` with `Cache-Control: private, no-store`.
  - anonymous requests get 401 JSON;
  - token requests get 403 `token_not_allowed`, because the action is not opened.
- **`Api::DocsController < ApplicationController`, `show`** renders the HTML page with its own layout, `api_docs`.
  - anonymous visitors get the page controllers' redirect to sign-in, which remembers `/api/docs`;
  - it includes `ApiTokenAuthentication` with nothing opened, and its `render_token_error` renders the same JSON envelope as the API, so the route-table test's expectation holds.

The page is product documentation for the user's own data, not an operational or debug surface. The security-baseline rule "Operational surfaces are administrator-only" does not apply, and no spec change is needed there.

*Alternatives:*
- *Docs inside the SPA at `/app/api-docs`.* Rejected. The SPA's dependency and CSS rules would have to admit the viewer, which would also land in the SPA's bundle graph.
- *Make `Api::DocsController` inherit `Api::BaseController`.* Rejected. Anonymous visitors to an HTML page should get the sign-in redirect, not 401 JSON.

### 6. Swagger UI from npm, in its own Vite entrypoint

`swagger-ui-dist` is added at an exact version as a runtime dependency. A second Vite input, `app/frontend/entrypoints/api-docs.ts`:
- imports `swagger-ui-dist/swagger-ui-bundle.js` and `swagger-ui-dist/swagger-ui.css`;
- reads the document URL from a `data-` attribute on its mount element, since inline scripts are forbidden;
- calls `SwaggerUIBundle({ domNode, url, deepLinking: true, persistAuthorization: false, requestInterceptor })`.

The layout loads it with `vite_tags("api-docs.ts")`. A small `.d.ts` file declares the one function used.

`script/check-frontend-policy.mjs` gains two rules:
- `swagger-ui-dist` is allowed and required;
- only `app/frontend/entrypoints/api-docs.ts` may import it.

`swagger-ui-dist` is chosen over the `swagger-ui` source package. It is prebuilt with one transitive dependency, `@scarf/scarf`, instead of the dozens React and Redux would add. Its size, about 1.5 MB, loads only on the docs page.

*Alternatives:*
- *Vendor the bundle into `vendor/` or `public/`.* Rejected. A vendored file is outside `package-lock.json`, so osv-scanner and Dependabot would never see its advisories, which goes against the security-baseline dependency gate.
- *Redoc.* Rejected. It injects `<style>` elements through styled-components, which the CSP forbids, and it has no "Try it out".

### 7. "Try it out" without the session

The `requestInterceptor` sets `credentials: "omit"` on every request except the document fetch, which Swagger UI marks with `loadSpec`. The document fetch needs the session cookie, because `/api/openapi.yaml` is for signed-in users only.

Calls from the page therefore carry only the token entered through "Authorize" (the `bearerAuth` scheme). Without a token they get 401, like an external client. `persistAuthorization: false`, Swagger UI's default made explicit, keeps the token out of `localStorage`.

Ignoring the cookie is also what the server does in token mode. Omitting it covers the case with no token, where the session would otherwise authenticate GET requests.

### 8. The verification command

`bin/openapi-verify` is a shell script, alongside `bin/ci` and `bin/brakeman`. It runs `bin/rails db:test:prepare` quietly, then `bin/rails test` with the contract files, and exits with the test run's status. Failures name the operation, method and path, status or field, as the spec asks.

- **Kept out of the default run by the file names.** The contract files end in `_contract.rb`. `bin/rails test`, and therefore CI, loads only `test/**/*_test.rb` (and never `test/system`), so it never sees them. The command passes them explicitly. The CI workflow is not changed.
- **Fit for a git hook.** It needs no running server, no network and no input. It prints a one-line summary and returns a status a `pre-push` hook can act on. The hook itself is installed separately (proposal.md, "Not included").
- **Runs in parallel.** It uses the same parallel workers as the default suite, which is safe because every check is per test (decisions 2 to 4).

*Alternatives:*
- *A rake task, `bin/rails openapi:verify`.* Workable, but a `bin/` script is simpler to call from a hook and matches `bin/ci`. The script stays a thin wrapper, so a rake task can be added later if wanted.
- *Keep the files as `*_test.rb` and skip them unless an environment variable is set.* Rejected. Every default run would print skipped tests, and the default suite would quietly depend on the environment.
- *Exclude a directory with `DEFAULT_TEST_EXCLUDE`.* Rejected. CI and every developer would have to set it, so the default run would be wrong whenever they did not.

### 9. Links

- The API tokens screen's intro gains a link, "API reference", to `/api/docs` (in `en` and `ru`).
- The docs page header links back to `/app/settings/api-tokens`, to create a token.
- The README's "API tokens" section points to `/api/docs` and `/api/openapi.yaml` instead of `config/routes.rb`.

## Risks / Trade-offs

- **[Swagger UI breaks the production CSP: injected `<style>`, `eval`, or a style attribute set by markup]** → The first implementation task renders the page under the production policy in a system test, before any documentation is written. If it reports violations, implementation stops and the choice goes back to the user: a CSP exception scoped to `/api/docs` would need a security-baseline change, or a different viewer.
- **[`@scarf/scarf` is install-time telemetry]** → Its postinstall script never runs, because the project installs with `--ignore-scripts` (spec security-baseline). The system test asserts that the page requests nothing from another origin.
- **[`swagger-ui-dist` has no ES module entry]** → Vite and Rolldown handle the CommonJS bundle through interop. If the import misbehaves, the entrypoint loads the bundle's global instead. Tasks 1.2 and 1.3 settle this before anything else is built.
- **[Strict response schemas make adding a field a two-file change]** → This is intended: a new field is part of the public contract and is documented when it appears. The test failure names the field.
- **[The document and `types.ts` duplicate each other]** → They are accepted as separate for now (non-goal). The verification checks the document against the serializers; `types.ts` stays checked by the SPA's own tests.
- **[The document drifts, because CI no longer checks it]** → This is accepted by choice. A planned `pre-push` hook runs `bin/openapi-verify` before every push, and the README tells contributors to run it when they touch a serializer or an opened action. Every failure names what to fix.
- **[Behavior only the existing token tests reach, such as a rare status, is not validated]** → The error examples cover each error kind, the document check covers the listed responses, and the examples cover each operation's success. A status that appears only in an edge case can still go unnoticed until someone documents it.
- **[The command gets too slow for a pre-push hook]** → The 429 example sends 301 requests, and everything else is one request per test. Task 3.7 measures the command's runtime; the target is under 30 seconds on a developer machine.
- **[openapi_first's API differs between versions]** → The gem is pinned. Task 2.1 verifies `OpenapiFirst.load` / `validate_request` / `validate_response` with `raise_error:` in the pinned version before the hook is written.

## Migration Plan

1. Purely additive: two GET routes, a docs page, a test-only gem, an npm package and a second Vite entrypoint. No data changes.
2. Whatever builds the SPA (`npx vite build`) now also builds `api-docs.ts`, with no extra step. The Dockerfile does not build the frontend today; that gap predates this change and is out of its scope.
3. Rollback: revert the change. Tokens and the API are unaffected.
