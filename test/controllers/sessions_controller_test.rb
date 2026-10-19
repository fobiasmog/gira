require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "correct credentials sign in and land on /app" do
    sign_in_with @user.email_address

    assert_redirected_to app_path
    assert cookies[:session_id].present?
    assert signed_in?
  end

  test "correct credentials return to the originally requested page" do
    get app_path("projects/1")
    assert_redirected_to new_session_path

    sign_in_with @user.email_address

    assert_redirected_to app_path("projects/1")
  end

  test "unknown email and wrong password get the same generic error" do
    sign_in_with "nobody@example.com"
    unknown = [ response.status, flash[:alert] ]

    sign_in_with @user.email_address, "wrong password!"

    assert_equal unknown, [ response.status, flash[:alert] ]
    assert_equal [ 422, I18n.t("sessions.invalid") ], unknown
    assert_nil cookies[:session_id].presence
  end

  test "sign-in before confirmation" do
    sign_in_with users(:unconfirmed).email_address

    assert_redirected_to new_confirmation_path
    assert_equal I18n.t("sessions.unconfirmed"), flash[:alert]
    assert_not signed_in?
  end

  test "an unconfirmed account with a wrong password gets the generic error" do
    sign_in_with users(:unconfirmed).email_address, "wrong password!"

    assert_response :unprocessable_content
    assert_equal I18n.t("sessions.invalid"), flash[:alert]
  end

  test "the tenth consecutive wrong password locks the account and emails an unlock link" do
    9.times { sign_in_with @user.email_address, "wrong password!" }
    assert_not @user.reload.locked?

    sign_in_with @user.email_address, "wrong password!"

    assert @user.reload.locked?
    assert_enqueued_email_with AccountMailer, :unlock, args: [ @user ]
  end

  test "the correct password is refused while locked, with the same generic error" do
    lock @user

    sign_in_with @user.email_address

    assert_response :unprocessable_content
    assert_equal I18n.t("sessions.invalid"), flash[:alert]
    assert @user.reload.locked?
    assert_not signed_in?
  end

  test "the unlock link unlocks the account" do
    lock @user
    token = @user.generate_token_for(:unlock)

    get unlock_path(token)
    assert @user.reload.locked?, "opening the link must not unlock"

    patch unlock_path(token)
    assert_not @user.reload.locked?

    sign_in_with @user.email_address
    assert_redirected_to app_path
  end

  test "an unlock link works once" do
    lock @user
    token = @user.generate_token_for(:unlock)
    patch unlock_path(token)
    travel 1.second
    lock @user

    patch unlock_path(token)

    assert @user.reload.locked?
    assert_redirected_to new_unlock_path
  end

  test "the lock expires after an hour" do
    lock @user

    travel 61.minutes do
      sign_in_with @user.email_address
      assert_redirected_to app_path
    end
  end

  test "a successful sign-in resets the failed-attempt count" do
    5.times { sign_in_with @user.email_address, "wrong password!" }
    sign_in_with @user.email_address
    assert_equal 0, @user.reload.failed_login_attempts
    reset!

    sign_in_with @user.email_address, "wrong password!"

    assert_not @user.reload.locked?
    assert_equal 1, @user.failed_login_attempts
  end

  test "unlock links can be re-sent, with the same answer for any address" do
    lock @user

    post unlocks_path, params: { email_address: @user.email_address }
    assert_enqueued_email_with AccountMailer, :unlock, args: [ @user ]
    sent = { location: response.location, notice: flash[:notice] }

    assert_no_enqueued_emails do
      post unlocks_path, params: { email_address: users(:two).email_address }
    end
    assert_equal sent, { location: response.location, notice: flash[:notice] }
  end

  test "sign-in is limited to 10 attempts per 3 minutes per IP address, without checking credentials" do
    10.times { sign_in_with "nobody@example.com" }

    sign_in_with @user.email_address, "wrong password!"

    assert_response :too_many_requests
    assert_equal 0, @user.reload.failed_login_attempts
  end

  test "unlock re-sends are limited to 5 per hour per IP address" do
    lock @user
    5.times { post unlocks_path, params: { email_address: "nobody@example.com" } }

    assert_no_enqueued_emails do
      post unlocks_path, params: { email_address: @user.email_address }
    end
    assert_response :too_many_requests
  end

  private
    def lock(user)
      user.update_columns(failed_login_attempts: User::MAX_FAILED_SIGN_INS, locked_until: 1.hour.from_now)
    end
end
