# Development servers, one per terminal. bin/dev starts them together.
# Open the app at http://localhost:5173 (Vite passes non-/vite paths to Rails).
.PHONY: backend frontend livekit newuser seconduser

# Rails on port 3000. Pages under /app load the SPA from the Vite dev server
# (VITE_DEV_SERVER_HOST, default localhost:5173).
backend:
	bin/rails server

# The Vite dev server for the SPA. Run `npm ci` once first.
frontend:
	npx vite

# The LiveKit media server for calls, in development mode (key devkey, secret
# secret, on ws://localhost:7880). Install it with `brew install livekit`.
livekit:
	livekit-server --dev

newuser:
	bin/rails runner 'User.find_or_create_by!(email_address: "test-1@test.com") { |u| u.name = "Test 1"; u.password = "password1234"; u.confirmed_at = Time.current }'

# A second user who shares a project with the first, for trying calls in two
# browser profiles. Uses the first user's oldest project, or creates one.
seconduser: newuser
	bin/rails runner 'first = User.find_by!(email_address: "test-1@test.com"); second = User.find_or_create_by!(email_address: "test-2@test.com") { |u| u.name = "Test 2"; u.password = "password1234"; u.confirmed_at = Time.current }; project = Project.kept.where(owner: first).order(:id).first || Project.create!(owner: first, title: "Shared project", short_name: "SHARED"); project.memberships.find_or_create_by!(user: second); puts "test-1@test.com and test-2@test.com share #{project.title}"'
