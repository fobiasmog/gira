require "test_helper"

class SessionLifetimeTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "idle session: a user returning after 15 days must sign in again" do
    sign_in_with @user.email_address

    travel 15.days do
      get app_path
      assert_redirected_to new_session_path
    end
  end

  test "active session: using the application every few days keeps it valid" do
    sign_in_with @user.email_address

    5.times do |visit|
      travel 10.days
      get app_path
      assert_response :success, "visit #{visit + 1}"
    end
  end

  test "use is recorded at most once per hour" do
    sign_in_with @user.email_address
    session = @user.sessions.last

    travel 30.minutes do
      assert_no_changes -> { session.reload.updated_at } do
        get app_path
      end
    end
    travel 2.hours do
      assert_changes -> { session.reload.updated_at } do
        get app_path
      end
    end
  end

  test "stolen cookie after sign-out is treated as unauthenticated" do
    sign_in_with @user.email_address
    stolen = cookies[:session_id]

    delete session_path
    assert_redirected_to root_path
    assert_empty @user.sessions.reload

    cookies[:session_id] = stolen
    get app_path
    assert_redirected_to new_session_path
  end

  test "a GET to the sign-out URL keeps the user signed in" do
    sign_in_with @user.email_address

    get "/session"

    assert_response :not_found
    assert_equal 1, @user.sessions.count
    assert signed_in?
  end

  test "the session cookie is Secure, HttpOnly and SameSite=Lax over HTTPS" do
    https!
    sign_in_with @user.email_address

    cookie = Array(response.headers["Set-Cookie"]).join("\n").lines.find { |line| line.start_with?("session_id=") }
    assert_match(/; secure/i, cookie)
    assert_match(/; httponly/i, cookie)
    assert_match(/; samesite=lax/i, cookie)
    assert_match(/; expires=/i, cookie)
  end

  test "an API call without a session gets 401 JSON" do
    patch api_me_password_path, params: { current_password: "x", password: "y" }, as: :json

    assert_response :unauthorized
    assert_equal "unauthorized", response.parsed_body.dig("error", "code")
  end

  test "sessions do not store IP addresses" do
    assert_not_includes Session.column_names, "ip_address"
  end
end
