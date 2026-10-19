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

class SpaControllerAnonymousTest < ActionDispatch::IntegrationTest
  test "anonymous visitors are sent to sign in and come back afterwards" do
    get "/app/projects/1"

    assert_redirected_to new_session_path
    sign_in_with users(:one).email_address
    assert_redirected_to "http://www.example.com/app/projects/1"
  end
end
