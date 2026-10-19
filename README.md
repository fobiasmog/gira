# README

## Development

Prerequisites: Ruby (see `.ruby-version`), Node 22.18 or newer, PostgreSQL 18 and libvips.

libvips is required even for a bare start: every new user gets a generated
default avatar. Without it, creating a user fails with the misleading
`uninitialized constant Vips::Image` (Active Storage swallows the real "could
not open library 'vips'" error). On macOS:

```sh
brew install vips
```

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

Для дат всегда юзать ```.current``` ибо он возвращает с учётом ```Time.zone```


Дамп с базы
```pg_dump -O -U deadline -b -Ft -c --if-exists  > deadline.tar```
