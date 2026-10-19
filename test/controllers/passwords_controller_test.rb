require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "reset requested for a known email sends a link" do
    post passwords_path, params: { email_address: @user.email_address }

    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to new_session_path
  end

  test "reset requested for an unknown email gets the same answer and sends nothing" do
    post passwords_path, params: { email_address: @user.email_address }
    known = { location: response.location, notice: flash[:notice] }

    assert_no_enqueued_emails do
      post passwords_path, params: { email_address: "nobody@example.com" }
    end
    assert_equal known, { location: response.location, notice: flash[:notice] }
  end

  test "expired reset link" do
    token = @user.password_reset_token

    travel 16.minutes do
      get edit_password_path(token)
    end

    assert_redirected_to new_password_path
    assert_equal I18n.t("passwords.invalid"), flash[:alert]
  end

  test "reset completes: password changed, link used up, all sessions ended" do
    other_device = @user.sessions.create!
    token = @user.password_reset_token

    put password_path(token), params: { password: "a brand new password", password_confirmation: "a brand new password" }

    assert_redirected_to new_session_path
    assert @user.reload.authenticate("a brand new password")
    assert_not Session.exists?(other_device.id)

    get edit_password_path(token)
    assert_redirected_to new_password_path
  end

  test "an invalid new password is rejected and the link stays usable" do
    token = @user.password_reset_token

    put password_path(token), params: { password: "short", password_confirmation: "short" }

    assert_response :unprocessable_content
    assert @user.reload.authenticate(PASSWORD)
    get edit_password_path(token)
    assert_response :success
  end

  test "mismatched confirmation is rejected" do
    put password_path(@user.password_reset_token), params: { password: "a brand new password", password_confirmation: "another password!" }

    assert_response :unprocessable_content
    assert @user.reload.authenticate(PASSWORD)
  end

  test "reset requests are limited to 5 per hour per IP address" do
    5.times { post passwords_path, params: { email_address: "nobody@example.com" } }

    assert_no_enqueued_emails do
      post passwords_path, params: { email_address: @user.email_address }
    end
    assert_response :too_many_requests
  end
end
