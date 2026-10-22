# Tasks

## 1. Development setup

- [x] 1.1 Add `brew install livekit` to the README prerequisites, with a note that calls need it, and describe two-profile testing; verify the README renders and the commands are correct by running them on a clean shell
- [x] 1.2 Make `bin/dev` start `livekit-server --dev` alongside Vite and Puma when `livekit-server` is on the path, and print a one-line notice otherwise; verify with and without the binary on `PATH` that Ctrl-C stops every process
- [x] 1.3 Add a `livekit` target and a target that creates a second confirmed user sharing a project with the first to the `Makefile`; verify both users can sign in and see the shared project

## 2. Configuration and browser policy

- [x] 2.1 Set `config.x.livekit` in `development.rb` and `test.rb` (`LIVEKIT_URL` or `ws://localhost:7880`, `devkey` / `secret`) and in `production.rb` from `credentials.livekit` (`nil` when absent); document the `livekit` key in `config/credentials.example.yml`; verify `bin/rails runner 'p Rails.configuration.x.livekit'` in development and with `RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1`
- [x] 2.2 Add the media server's WebSocket origin and its HTTP equivalent to `connect-src` in `content_security_policy.rb` when `config.x.livekit` is present; verify with a request test for both the configured and the unconfigured case
- [x] 2.3 Change the Permissions-Policy to `camera=(self), microphone=(self), geolocation=(), payment=(), usb=()`; verify with a request test for the "Camera and microphone for own pages only" scenario

## 3. LiveKit client

- [x] 3.1 Add `LiveKit::AccessToken` in `lib/live_kit/` (HS256 JWT: `iss`, `sub`, `name`, `nbf`, `exp`, `video` grant); verify a unit test that checks the signature with the secret and every claim, including the 10-minute expiry
- [x] 3.2 Add `LiveKit::RoomService` with `list_participants`, `remove_participant` and `delete_room` over Twirp JSON with `Net::HTTP`, an injectable transport, a short-lived admin token per room, 2-second timeouts, and "room not found" treated as empty; verify unit tests with a fake transport for request paths, bodies, the auth header and error handling

## 4. Project call and API

- [x] 4.1 Add `ProjectCall` (room name, identity, token for a member with the grant from design.md, participants filtered through the project's members, cached for 5 seconds, `evict(user)`, `close`, `available?`) with its room service as a swappable class attribute, plus an in-memory fake room service for tests; verify model tests for the token grant, member filtering and the unavailable case
- [x] 4.2 Add `resource :call, only: :show` with a nested `resource :token, only: :create` under projects, `Api::Projects::CallsController#show` and `Api::Projects::Calls::TokensController#create` (with `rate_limit_per_user to: 20, within: 1.minute`, 404 when unavailable); verify request tests for the scenarios "Not a member", "Archived project", "No personal data beyond the name", "Too many token requests", an unreachable LiveKit (empty list, no 500) and the unconfigured response
- [x] 4.3 Add `CallEvictionJob` (remove a participant, or delete the room when no user is given; no-op without settings; `retry_on` network errors) and enqueue it from `Project#remove_member!` after its transaction and from `Project#archive!`; verify job tests and model tests that removal, leaving and archiving enqueue it with the right arguments

## 5. Client foundation

- [x] 5.1 Add `livekit-client` at an exact version to `package.json`, update `package-lock.json` with `npm install --ignore-scripts`, and add it to `RUNTIME_REQUIRED` in `script/check-frontend-policy.mjs`; verify `npm run policy`, `npm audit signatures` and `npm ci --ignore-scripts` succeed
- [x] 5.2 Move `readStored`/`writeStored` from `stores/ui.ts` into a shared module and use it from the `ui` store; verify `npm run typecheck` and the existing sidebar system tests pass
- [x] 5.3 Add `api/call.ts` (`getCall`, `createToken`) and the response types to `api/types.ts`; verify `npm run typecheck`
- [x] 5.4 Add `composables/callState.ts` (view transitions, participant ordering, pane-width clamping, parsing of stored media preferences, disconnect reason to message key) with `node --test` tests; verify `npm test`
- [x] 5.5 Add the icons `call`, `call_end`, `mic`, `mic_off`, `videocam`, `videocam_off`, `open_in_full`, `close_fullscreen`, `keyboard_arrow_down` and `volume_up` to the sprite from Material Symbols Outlined 400, and the `call.*` strings with counted forms to `i18n/en.ts` and `i18n/ru.ts`; verify `npm test` (key parity) and that each icon renders on the components fixture page

## 6. Call store

- [x] 6.1 Add `stores/call.ts`: dynamic import of `livekit-client`, `join(projectId)` (token, connect with `adaptiveStream`, `dynacast` and 360p capture, remembered microphone and camera state with per-device error notices), `leave()`, toggles, device listing and switching, `startAudio()`, `view`, the `Room` kept with `markRaw`, participant view models from room events, member cards for avatars (reloaded once for an unknown identity), announcements through `ui.announce()`, and disconnect reasons mapped to toasts; verify `npm run typecheck` and `npm run build` (`livekit-client` is in a separate chunk)

## 7. Call views

- [x] 7.1 Add `CallTile.vue`, `CallTiles.vue` and `CallControls.vue` (video attached with `track.attach` to `<video playsinline muted>`, avatar when the camera is off, name, muted marker, speaking highlight, mirrored own tile labelled "You", device menus on `AppMenu`, Leave); verify `npm run policy` reports no HTML sink and `npm run typecheck` passes
- [x] 7.2 Add `CallAudio.vue`, always mounted during a call, which attaches remote audio tracks to its own `<audio>` elements; verify sound continues in the bar and tab views in a manual two-profile check
- [x] 7.3 Add `CallPane.vue` with the project title linking to its board, and a splitter (`role="separator"`, value attributes, arrow keys in 16px steps, pointer capture, 240–480px, default 320px, stored as `goalner.callPaneWidth`); make the `AppShell.vue` grid `auto minmax(0, 1fr) auto` and render the pane on wide screens when `view` is `expanded`; verify the board narrows and stays scrollable in a manual check
- [x] 7.4 Add `CallOverlay.vue` as a native modal `<dialog>` for narrow screens whose `cancel` event shrinks the call to the bar; verify in Chrome device emulation that focus stays inside and Escape shows the bar
- [x] 7.5 Add `CallBar.vue` and `CallTab.vue`, fixed at the bottom, and set `--call-dock-height` (with the bottom safe-area inset) as bottom padding of `.shell__content`; verify on wide and narrow screens that the last backlog task scrolls fully above the bar

## 8. Board header

- [x] 8.1 Add `CallButton.vue` to the header actions of `BoardPage.vue`: "Start call", "Join call" with up to three avatars and the count, or "In call"; polling every 20 seconds (1 second in `--mode test` builds) only while the page is visible and the member is not in this call; a refresh when the page becomes visible; nothing when unavailable; and a `ConfirmDialog` before switching from another project's call; verify `npm run typecheck` and a manual check in both layouts

## 9. CI

- [ ] 9.1 In `.github/workflows/ci.yml`, download a pinned `livekit-server` Linux release with a SHA-256 check (version and checksum in workflow env, as for `osv-scanner`) and start it with `--dev` before the system tests; verify the workflow passes on a pull request
- [x] 9.2 Add a system test base for call tests that starts Chrome with `--use-fake-ui-for-media-stream --use-fake-device-for-media-stream`, and helpers to join as a second user with `using_session` and to wait for a remote `<video>` with a non-zero `videoWidth`; verify one smoke test passes locally against `livekit-server --dev`

## 10. Verification

- [x] 10.1 Add system tests for the `team-call` scenarios "Start a call", "Join a running call", "No media server configured", "Somebody in the call", "Participants refresh", "Member already in the call", "Turn the camera off", "Mute", "Choice remembered", "Camera access refused" (permission overridden through the DevTools Protocol), "Own tile", "Join announced", "Open a task during a call", "Another project during a call", "Switch to another project's call", "Leave", "Reload during a call", "Pane appears", "Resize with the keyboard", "Width limits", "Join on a phone", "Escape shrinks the call", the bar and tab scenarios, "Removed during a call", "Project archived during a call" (with `perform_enqueued_jobs`), "Join from a second tab" and "Media server unreachable"; verify `bin/rails test:system` passes with no CSP violations
- [x] 10.2 Add a system test that reconnects after the original token has expired, using a short `token_ttl` in the test's `config.x.livekit` (LiveKit checks expiry against its own clock, so time travel in Rails does not help); verify it passes, or else implement requesting a new token before reconnecting and verify again
- [ ] 10.3 Check manually what system tests cannot cover well: "Short interruption" (DevTools offline for a few seconds), "Choose another microphone" with two real devices, the "Enable sound" control when autoplay is blocked, and the speaking highlight with real voices; record the results in the pull request
- [x] 10.4 Run the full suite (`bin/rails test test:system`), `npm test`, `npm run typecheck`, `npm run policy` and `bin/brakeman`; verify all pass
