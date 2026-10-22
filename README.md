# README

## Development

Prerequisites: Ruby (see `.ruby-version`), Node 22.18 or newer, PostgreSQL 18,
libvips and, for team calls, the LiveKit server.

libvips is required even for a bare start: every new user gets a generated
default avatar. Without it, creating a user fails with the misleading
`uninitialized constant Vips::Image` (Active Storage swallows the real "could
not open library 'vips'" error). On macOS:

```sh
brew install vips
```

### LiveKit (team calls)

Team calls need a LiveKit media server. Without it the app runs, but calls
do not connect: "Start call" shows "Could not connect to the call", and Rails
logs a warning on each participant check. The call system tests
(`test/system/call_*_test.rb`) fail without it.

On macOS:

```sh
brew install livekit
```

On Linux, take the release binary that CI pins (`LIVEKIT_VERSION` in
`.github/workflows/ci.yml`, currently v1.13.10) from
https://github.com/livekit/livekit/releases, check it against the release's
`checksums.txt`, and put `livekit-server` on your `PATH`:

```sh
curl -sSfLO https://github.com/livekit/livekit/releases/download/v1.13.10/livekit_1.13.10_linux_amd64.tar.gz
curl -sSfLO https://github.com/livekit/livekit/releases/download/v1.13.10/checksums.txt
sha256sum --check --ignore-missing checksums.txt
tar -xzf livekit_1.13.10_linux_amd64.tar.gz livekit-server
sudo mv livekit-server /usr/local/bin/
```

Use `linux_arm64` instead of `linux_amd64` on ARM machines.

`bin/dev` starts it in development mode when `livekit-server` is on your
`PATH` (its log goes to `log/livekit.log`), and `make livekit` starts it on its
own. Development mode listens on ws://localhost:7880 with the published key
`devkey` and secret `secret`, which `config/environments/development.rb` and
`test.rb` expect; set `LIVEKIT_URL` to use a server elsewhere.

The browser side comes from the `livekit-client` npm package, so an existing
checkout needs `npm ci` again after pulling this change.

Setup:

```sh
bundle install
npm ci
bin/rails db:prepare
```

Development has no mail delivery, so sign-up confirmation emails never arrive.
Create a confirmed user from the command line instead (passwords need at least
12 characters):

```sh
bin/rails runner 'User.find_or_create_by!(email_address: "you@example.com") { |u| u.name = "Your Name"; u.password = "your long password"; u.confirmed_at = Time.current }'
```

Run the servers in two terminals with `make backend` (Rails on port 3000) and
`make frontend` (Vite on port 5173), or both at once with `bin/dev`. Then open
http://localhost:5173 and sign in. Vite passes every path outside `/vite/` on
to Rails, so the whole app runs on one origin, which the SVG icon sprite needs
(browsers refuse a sprite from another origin, whatever its CORS headers).
Opening `/app` on port 3000 redirects to the same path on port 5173.

To try a call with two people, create a second confirmed user who shares a
project with the first (`make newuser` creates the first, test-1@test.com):

```sh
make seconduser
```

Then sign in as test-1@test.com in one browser profile and as test-2@test.com
(password `password1234` for both) in another, for example a second Chrome
profile or a private window, open the board of the shared project in both and
start the call. Browsers allow the camera and microphone on
http://localhost without HTTPS.

Для дат всегда юзать ```.current``` ибо он возвращает с учётом ```Time.zone```


Дамп с базы
```pg_dump -O -U deadline -b -Ft -c --if-exists  > deadline.tar```
