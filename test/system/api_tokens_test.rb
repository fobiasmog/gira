require "application_system_test_case"

# Spec web-client, "API tokens screen".
class ApiTokensTest < ApplicationSystemTestCase
  PASSWORD = "correct horse battery"

  setup do
    @user = users(:one)
    sign_in @user.email_address, PASSWORD
  end

  def fill_in_token_form(name:, password:)
    fill_in "Name", with: name
    select "Goalner", from: "Project"
    choose "Read and write"
    select "90 days", from: "Expires in"
    fill_in "Current password", with: password
  end

  test "create and copy: the value is shown once with a warning, and the token is listed" do
    visit "/app/settings/api-tokens"

    fill_in_token_form name: "CI", password: PASSWORD
    click_button "Create token"

    assert_text "Copy it now. It will not be shown again."
    value = find_field("Token").value
    assert_match(/\Aglnr_\w{40}\z/, value)
    execute_script("navigator.clipboard.writeText = async (text) => { window.__copied = text }")
    click_button "Copy"
    assert_text "Token copied"
    assert_equal value, evaluate_script("window.__copied")

    within(".tokens") do
      assert_text "CI"
      assert_text "Goalner · Read and write · ends in #{value.last(4)}"
    end
    token = @user.api_tokens.find_by!(name: "CI")
    assert_equal [ projects(:goal), "read_write" ], [ token.project, token.access ]
    assert_in_delta 90.days.from_now, token.expires_at, 1.minute
  end

  test "value not shown again after leaving the screen" do
    visit "/app/settings/api-tokens"
    fill_in_token_form name: "CI", password: PASSWORD
    click_button "Create token"
    value = find_field("Token").value

    click_link "Profile"
    assert_field "Language"
    click_link "API tokens"

    within(".tokens") { assert_text "CI" }
    assert_no_field "Token"
    assert_no_text value
  end

  test "wrong password: the error is under the password field and the other fields keep their values" do
    visit "/app/settings/api-tokens"

    fill_in_token_form name: "CI", password: "not my password"
    click_button "Create token"

    assert_invalid_field "Current password"
    assert_text "Current password is invalid"
    assert_field "Name", with: "CI"
    assert_select "Project", selected: "Goalner"
    assert_checked_field "Read and write"
    assert_select "Expires in", selected: "90 days"
    assert_not @user.api_tokens.exists?(name: "CI")
  end

  test "revoke after confirming: the token disappears from the list" do
    token = api_tokens(:one_goal_read_write)
    visit "/app/settings/api-tokens"
    within(".tokens") { assert_text "Bot" }

    click_button "Revoke token Bot"
    within("dialog") { click_button "Revoke" }

    assert_text "Token “Bot” revoked"
    assert_text "You have no API tokens."
    assert_not ApiToken.exists?(token.id)
  end

  test "the password change form warns that it revokes API tokens" do
    visit "/app/settings/security"

    assert_text "Changing your password revokes all your API tokens."
  end

  test "the API tokens screen links to the API documentation" do
    visit "/app/settings/api-tokens"

    click_link "API reference"

    assert_current_path "/api/docs"
    assert_selector ".opblock-summary-path", text: "/api/me"
  end
end
