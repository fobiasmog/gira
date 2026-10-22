# Design

## Context

The application has no real-time layer. Action Cable was left out on purpose when the backend was rebuilt (`config/application.rb`), so every screen loads data over the JSON API only. The constraints that shape this change:

- `security-baseline` sends `Permissions-Policy: camera=(), microphone=()`, limits `connect-src` to the own origin and the Sentry ingest host, and allows no other third-party destination. The specs in this change amend all three.
- `web-client` allows only an exact list of runtime packages, enforced by `script/check-frontend-policy.mjs`, and forbids HTML sinks outside `MarkdownView.vue`.
- The shell (`AppShell.vue`) is a grid of `auto minmax(0, 1fr)`: a sidebar that may be collapsed to a rail, and the main column. Below 1024px the sidebar becomes a drawer. The board (`.board`) already scrolls horizontally, so a narrower main column needs no board changes.
- Opening a task card is a route change (`TaskCard.vue` links to the `task` route). A call owned by `BoardPage` would end on that click.
- There is no production deployment yet. This change targets the development setup and CI only.
- Tests: Minitest 6, without `minitest/mock`. System tests run headless Chrome and fail on CSP violations in the browser console. The test suite has no HTTP stubbing library.

## Goals / Non-Goals

**Goals:**
- A call per project with audio and video, through a self-hosted LiveKit server, with the application deciding who may join.
- The call state lives in the client for the whole page lifetime, independent of the current route.
- A development setup that needs one `brew install` and starts with `bin/dev`, and CI system tests that exercise a real media path.

**Non-Goals:**
- Action Cable, LiveKit webhooks and live board updates. These come with the collaboration work.
- Production deployment of the media server (TLS, TURN, ports, Kamal accessory).
- HTTPS in development, and therefore testing with real phones on the local network.

## Decisions

### 1. LiveKit as a selective forwarding unit, self-hosted
Each browser sends its streams once to LiveKit, which forwards them to the other participants. Simulcast plus `adaptiveStream` let each receiver get the resolution of the tile that shows the stream. `dynacast` stops layers that nobody watches. Because all media goes through the server, no participant's browser learns another participant's IP address. The `security-baseline` delta relies on this.
*Alternatives:* a peer-to-peer mesh over the browser API (no media server, but each participant uploads one stream per peer, which limits calls to about five people, and it exposes IP addresses between participants). LiveKit Cloud (no operations, but a second third-party destination that carries the media). Rejected in exploration in favour of self-hosting.

### 2. Rails issues tokens and lists participants; LiveKit does signaling
The browser connects directly to LiveKit with a token from Rails. Rails never relays signaling, so it needs no WebSocket support. Rails talks to LiveKit's server API for three things only: listing a room's participants, removing a participant, and deleting a room. No webhooks are received. That keeps the "deny by default" rule without an exception for an unauthenticated endpoint.
*Alternative:* webhooks for participant changes. Rejected for now: they need an unauthenticated endpoint, and pushing the result to browsers would need Action Cable as well.

### 3. A hand-written LiveKit client instead of `livekit-server-sdk`
The gem pulls in `faraday`, `jwt`, `twirp` and `google-protobuf`, the dependency chain the backend rebuild removed along with omniauth. The two needs are small:
- `LiveKit::AccessToken` (in `lib/live_kit/`) builds an HS256 JWT with `OpenSSL::HMAC`: `iss` is the API key, `sub` is the identity, `name`, `nbf`, `exp`, and a `video` grant.
- `LiveKit::RoomService` posts JSON to the Twirp endpoints `/twirp/livekit.RoomService/{ListParticipants,RemoveParticipant,DeleteRoom}` with `Net::HTTP`. It authenticates with a short-lived admin token for the one room and uses 2-second open and read timeouts. A missing room counts as an empty one.

Both are covered by unit tests. The system tests check them against a real LiveKit server.

### 4. Settings in the environment files, read by the CSP initializer
`config.x.livekit` holds `url`, `api_key` and `api_secret`, or is `nil` when calls are unavailable:
- `development.rb` and `test.rb` set `ws://localhost:7880` (overridable with `LIVEKIT_URL`) with the key `devkey` and secret `secret`. These are the fixed values of `livekit-server --dev`, published by LiveKit, so they are not secrets.
- `production.rb` reads `Rails.application.credentials.livekit` and stays `nil` without it. The key is documented in `config/credentials.example.yml` but not yet listed in `RequiredSecrets`. The production deployment change adds it there.

Environment files run before initializers, so `content_security_policy.rb` can add the media server's WebSocket origin and its HTTP equivalent to `connect-src` when `config.x.livekit` is present. The client calls the HTTP address to diagnose a failed connection.
*Alternative:* an initializer of its own. Rejected: initializers load alphabetically, after `content_security_policy.rb`.

### 5. `ProjectCall` and the API
`ProjectCall` (`app/models/project_call.rb`) wraps one project's call. The room name is `project-<id>`, and the identity is the user's id as a string. Its room service is a class attribute, so tests swap in an in-memory fake (there is no `minitest/mock`).

- `GET /api/projects/:project_id/call` (`Api::Projects::CallsController#show`) answers `{ available, participants }`. `participants` holds `UserSerializer#card`s of the identities LiveKit reports, filtered through `@project.members`, so a stale or foreign identity is never shown. The identity list is cached for 5 seconds per project in Solid Cache. When LiveKit cannot be reached, the response has an empty list and Rails logs a warning. It is not reported to Sentry, because a development machine without a running LiveKit server would otherwise report on every poll. Without settings, the response is `{ available: false, participants: [] }`.
- `POST /api/projects/:project_id/call/token` (`Api::Projects::Calls::TokensController#create`) answers `{ url, token }`. It is limited with `rate_limit_per_user to: 20, within: 1.minute`, and answers 404 without settings. The token:
  - is valid for 10 minutes (an optional `token_ttl` in `config.x.livekit` shortens it, for the reconnect test);
  - carries the grant `{ roomJoin: true, room: "project-<id>", canPublish: true, canPublishSources: ["camera", "microphone"], canSubscribe: true, canPublishData: false }`;
  - holds the user's name and no metadata.

  Both endpoints include `ProjectScoped`, so non-members and archived projects get 404 as everywhere else.

Avatars are not sent to LiveKit. On joining, the client loads the existing `GET /api/projects/:id/members` and maps identities to member cards. It reloads the list once when an unknown identity appears.

### 6. Eviction through a background job
`Project#remove_member!` enqueues `CallEvictionJob.perform_later(project, user)` after its transaction, and `Project#archive!` enqueues `CallEvictionJob.perform_later(project)`. The job calls `RemoveParticipant` or `DeleteRoom`, and does nothing without settings. Running it as a job keeps the request free of HTTP calls to LiveKit, and `retry_on` covers short LiveKit outages. Putting it in the model covers member removal, leaving and archiving from every caller. When the client receives the disconnect reason (`PARTICIPANT_REMOVED`, `ROOM_DELETED`), it closes the call view and shows the message the spec requires.

### 7. Client state in `stores/call.ts`, outside the route tree
A Pinia setup store owns the call:
- **Connection:** `status` (`idle`, `connecting`, `connected`, `reconnecting`) and the project id and title.
- **Participants:** a view model per participant (identity, name, avatar, local or not, speaking, microphone and camera state).
- **Devices:** microphone and camera on or off, the chosen devices, and the audio-blocked flag.
- **Display:** `view` (`expanded`, `bar`, `tab`) and a notice, the reason a device is off or a call ended.

The LiveKit `Room` and its tracks are kept in module variables and passed around with `markRaw`. Vue's reactive proxies break class instances that use private fields. Room events update the plain view models.

`livekit-client` is imported dynamically in `join()`, so screens that never join a call do not download it. `join()`:
1. requests a token;
2. connects with `adaptiveStream`, `dynacast` and 360p camera capture;
3. turns the microphone and camera on or off from the remembered preferences, catching `NotAllowedError` and `NotFoundError` per device to set the notice.

Device switching uses `room.switchActiveDevice`. When `room.canPlaybackAudio` turns false, the call shows "Enable sound", which calls `room.startAudio()`. LiveKit disconnects on page unload, which ends the call on reload or close. No flag is stored, so nothing joins again automatically.

Pure logic goes into `composables/callState.ts` with `node --test` tests: view transitions, participant ordering (join order, own tile last), clamping the pane width, parsing stored preferences.

Disconnect reasons map to messages:
- `DUPLICATE_IDENTITY`: "the call continues in another tab or device"
- `PARTICIPANT_REMOVED` and `ROOM_DELETED`: "you no longer have access"
- `CLIENT_INITIATED`: no message
- anything else: a generic "the call was disconnected"

### 8. Shell layout and components
`AppShell.vue` becomes a grid of `auto minmax(0, 1fr) auto` and renders, from `components/call/`:
- `CallPane.vue` in the third column when the screen is wide and `view` is `expanded`. Its left edge is a splitter (`role="separator"`, `aria-orientation="vertical"`, `aria-valuemin/max/now`, focusable). Arrow keys change the width by 16px; pointer dragging uses pointer capture. The width is clamped to 240–480px, defaults to 320px, and is stored as `goalner.callPaneWidth`.
- `CallOverlay.vue` when the screen is narrow and `view` is `expanded`. It is a native `<dialog>` opened with `showModal()`, which contains focus and makes the page inert. Its `cancel` event (Escape) is prevented and switches `view` to `bar`, so Escape shrinks the call instead of closing it. `AppDialog` is not reused because it closes on Escape.
- `CallBar.vue` or `CallTab.vue`, fixed at the bottom, when `view` is `bar` or `tab`. The shell sets `--call-dock-height` (with `env(safe-area-inset-bottom)`) as bottom padding of `.shell__content`, so no content stays hidden under them.
- `CallAudio.vue`, always mounted during a call. It attaches every remote audio track to its own `<audio>` elements. Tiles unmount in the bar and tab views, but sound must continue.

The pane and the overlay share `CallTiles.vue` and `CallTile.vue`. A tile attaches its video track to its own `<video playsinline muted>` with `track.attach(el)` and detaches it on unmount, so no HTML strings are involved. The own tile is mirrored with a CSS transform. Both views share `CallControls.vue`: microphone and camera toggles, device menus built on the existing `AppMenu`, and Leave. Crossing the 1024px breakpoint only swaps components; the tracks stay in the store and attach to the new elements.

Joins and departures go through `ui.announce()` to the existing live region. The project title in the call view header links to that project's board.

### 9. Board header control
`CallButton.vue` sits in `.board-header__actions` of `BoardPage.vue`, so both layouts get it. It loads `GET …/call` on mount, then every 20 seconds while `document.visibilityState` is `visible` and the member is not in this project's call. It refreshes when the page becomes visible again and stops on unmount. Builds with `--mode test` use a 1-second interval, so system tests do not wait. It shows:
- "Start call" when nobody is in the call;
- "Join call" with up to three avatars and the count when somebody is;
- "In call" when the member is in this project's call, which sets `view` to `expanded`.

When the member is in another project's call, Join asks through `ConfirmDialog` first. Nothing is shown when `available` is false.

### 10. Remembered preferences
The `readStored`/`writeStored` helpers that `stores/ui.ts` added for the sidebar move to a shared module. The call stores two values with them: `goalner.callPaneWidth` and `goalner.callMedia` (`{ mic, cam, micId, camId }`, defaulting to both on). As with the sidebar, the values hold no personal data and survive sign-out.

### 11. Development and CI
- `README.md`: `brew install livekit` as a prerequisite for calls.
- `bin/dev`: starts `livekit-server --dev` next to Vite and Puma if `livekit-server` is on the path. Otherwise it prints one line saying calls will not connect. `Makefile` gets a `livekit` target, and a target that creates a second confirmed user sharing a project with the first, for two-profile testing.
- CI: the test job downloads a pinned `livekit-server` release for Linux. The version and SHA-256 sit in workflow env, as for `osv-scanner`. It starts the server with `--dev` before the system tests. It runs directly on the runner, so no UDP ports have to be mapped through Docker.
- Call system tests run Chrome with `--use-fake-ui-for-media-stream --use-fake-device-for-media-stream`. They use two Capybara sessions and check that the other participant's `<video>` reports a non-zero `videoWidth`, which proves media went through LiveKit. A refused permission is simulated by overriding the permission through the Chrome DevTools Protocol. Narrow-screen tests resize the window to 390×844.

### 12. Icons and strings
The sprite gets `call`, `call_end`, `mic`, `mic_off`, `videocam`, `videocam_off`, `open_in_full`, `close_fullscreen`, `keyboard_arrow_down` and `volume_up`. They are Material Symbols Outlined 400 from the same repository as the existing ones. Strings go under `call.*` in `en.ts` and `ru.ts`, with counted forms (`tc`) for the participant count.

## Risks / Trade-offs

- [A removed member who saved a token can rejoin until it expires] → tokens live 10 minutes, and eviction removes the live connection. The window is accepted for a team tool. A second eviction run after the token lifetime can close it later if needed.
- [Reconnecting after the original token expired] → the LiveKit server refreshes the tokens of connected participants, and the client uses the refreshed token when it reconnects. A system test reconnects after the token's `exp` to confirm it. If refresh does not cover a case, the client requests a new token before reconnecting.
- [Polling load] → one request per board viewer every 20 seconds, with LiveKit asked at most every 5 seconds per project. That is negligible at team scale, and live updates replace it when Action Cable arrives.
- [`livekit-client` size, or a CSP violation inside it] → it is loaded only on Join. The call system tests fail on any CSP violation, so a problem shows up before merge. Optional features that need workers (end-to-end encryption, noise filters) stay unused.
- [Hand-written JWT and Twirp calls drift from LiveKit's format] → unit tests pin the claims, and the CI system tests run against a real LiveKit server of a pinned version.
- [LiveKit not running in development] → Join shows the generic error, the board shows "Start call" without participants, and Rails logs a warning only.
- [iOS Safari behaviour is untested until an HTTPS environment exists] → layouts are checked with device emulation. The production deployment change adds checks on real devices.
- [The media server can see all media] → it runs on our own infrastructure. End-to-end encryption is a later option; it would need a worker and a matching CSP.
- [The in-flight `sprint-based-backlog` change edits board files] → this change touches only the header actions of `BoardPage.vue`. Whichever change lands second merges the header.

## Migration Plan

No database change. The feature appears only where `config.x.livekit` is set, which is development and test for now. A production deploy before the media server exists ships only the relaxed Permissions-Policy, and shows no call control. Rolling back removes the code; the stored browser keys then go unused and do no harm.

## Open Questions

- The `livekit-server` version to pin in CI and to name in the README is chosen when implementing: the latest stable release at that time.
