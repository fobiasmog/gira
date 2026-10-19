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
end
