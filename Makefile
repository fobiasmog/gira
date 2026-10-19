# Development servers, one per terminal. bin/dev starts both together.
# Open the app at http://localhost:5173 (Vite passes non-/vite paths to Rails).
.PHONY: backend frontend

# Rails on port 3000. Pages under /app load the SPA from the Vite dev server
# (VITE_DEV_SERVER_HOST, default localhost:5173).
backend:
	bin/rails server

# The Vite dev server for the SPA. Run `npm ci` once first.
frontend:
	npx vite

newuser:
	bin/rails runner 'User.find_or_create_by!(email_address: "test-1@test.com") { |u| u.name = "Test 1"; u.password = "password1234"; u.confirmed_at = Time.current }'
