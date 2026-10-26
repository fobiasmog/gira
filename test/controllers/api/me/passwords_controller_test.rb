require "test_helper"

class Api::Me::PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "wrong current password" do
    patch api_me_password_path, params: { current_password: "not my password", password: "a brand new password" }, as: :json

    assert_response :unprocessable_content
    assert response.parsed_body.dig("error", "fields", "current_password").present?
    assert @user.reload.authenticate(PASSWORD)
    assert_equal 1, @user.failed_login_attempts
  end

  test "wrong current passwords in settings count toward lockout: the tenth locks and emails an unlock link" do
    @user.update_columns(failed_login_attempts: 9)

    assert_enqueued_email_with AccountMailer, :unlock, args: [ @user ] do
      patch api_me_password_path, params: { current_password: "not my password", password: "a brand new password" }, as: :json
    end

    assert_response :unprocessable_content
    assert @user.reload.locked?
    assert @user.authenticate(PASSWORD)
  end

  test "re-entered password while locked: refused with the same error as a wrong one" do
    patch api_me_password_path, params: { current_password: "not my password", password: "a brand new password" }, as: :json
    wrong = response.parsed_body
    @user.update_columns(locked_until: 30.minutes.from_now)

    patch api_me_password_path, params: { current_password: PASSWORD, password: "a brand new password" }, as: :json

    assert_response :unprocessable_content
    assert_equal wrong, response.parsed_body
    assert @user.reload.authenticate(PASSWORD)
  end

  test "a correct current password resets the failed-attempt count" do
    @user.update_columns(failed_login_attempts: 5)

    patch api_me_password_path, params: { current_password: PASSWORD, password: "a brand new password" }, as: :json

    assert_response :no_content
    assert_equal 0, @user.reload.failed_login_attempts
  end

  test "a too-short new password is rejected" do
    patch api_me_password_path, params: { current_password: PASSWORD, password: "short" }, as: :json

    assert_response :unprocessable_content
    assert response.parsed_body.dig("error", "fields", "password").present?
    assert @user.reload.authenticate(PASSWORD)
  end

  test "other devices are signed out and the current one stays signed in" do
    other_device = @user.sessions.create!

    patch api_me_password_path, params: { current_password: PASSWORD, password: "a brand new password" }, as: :json

    assert_response :no_content
    assert @user.reload.authenticate("a brand new password")
    assert_not Session.exists?(other_device.id)
    assert signed_in?
  end

  test "API tokens revoked: every token of the user stops working and the current session stays signed in" do
    tokens = [ api_tokens(:one_goal_read_write), @user.api_tokens.issue(project: projects(:goal), name: "Other", access: "read", expires_in_days: 7).tap(&:save!) ]

    patch api_me_password_path, params: { current_password: PASSWORD, password: "a brand new password" }, as: :json

    assert_response :no_content
    tokens.each { |token| assert_not ApiToken.exists?(token.id) }
    assert ApiToken.exists?(api_tokens(:two_goal_read_write).id), "other users' tokens are kept"
    get api_me_path, headers: { "Authorization" => "Bearer glnr_one_goal_read_write" }
    assert_response :unauthorized
    assert signed_in?
  end
end
