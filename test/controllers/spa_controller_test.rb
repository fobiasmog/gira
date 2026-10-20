require "test_helper"
require "support/forgery_protected_integration_test"

class SpaControllerTest < ForgeryProtectedIntegrationTest
  test "every /app path renders the SPA layout for a signed-in user" do
    sign_in_as users(:one)

    get "/app/projects/1"

    assert_response :success
    assert_select "meta[name=csrf-token]"
    assert_select "script[type=module][src=?]", "/vite/assets/application-abc123.js"
    assert_select "div#app"
    assert_select "meta[name=sentry-dsn]", count: 0
  end
end

# Development with the Vite dev server: the SPA must be opened on the dev
# server's origin, or the icon sprite is refused as cross-origin.
class SpaControllerDevServerTest < ActionDispatch::IntegrationTest
  setup do
    @dev_server = Rails.configuration.x.vite.dev_server
    Rails.configuration.x.vite.dev_server = "http://localhost:5173"
  end

  teardown { Rails.configuration.x.vite.dev_server = @dev_server }

  test "a request that reached Rails directly is sent to the same path on the dev server" do
    host! "localhost:3000"
    get "/app/projects/1?user=2"

    assert_redirected_to "http://localhost:5173/app/projects/1?user=2"
  end

  test "a request passed on by the dev server is served" do
    host! "localhost:5173"
    sign_in_with users(:one).email_address
    get "/app/projects/1"

    assert_response :success
    assert_select "script[type=module][src=?]", "http://localhost:5173/vite/@vite/client"
  end
end

class SpaControllerAnonymousTest < ActionDispatch::IntegrationTest
  test "anonymous visitors are sent to sign in and come back afterwards" do
    get "/app/projects/1"

    assert_redirected_to new_session_path
    sign_in_with users(:one).email_address
    assert_redirected_to "http://www.example.com/app/projects/1"
  end
end
