require "application_system_test_case"
require "support/image_files"

# Spec web-client, profile and security settings.
class SettingsTest < ApplicationSystemTestCase
  include ImageFiles

  PASSWORD = "correct horse battery"

  setup do
    @user = users(:one)
    sign_in @user.email_address, PASSWORD
  end

  test "change the name" do
    visit "/app/settings/profile"

    fill_in "Name", with: "Ada Lovelace"
    click_button "Save name"

    assert_text "Saved"
    assert_selector "button[aria-label='Ada Lovelace']"
    assert_equal "Ada Lovelace", @user.reload.name
  end

  test "switching the language re-renders the interface without a reload" do
    visit "/app/settings/profile"
    execute_script("window.__sameDocument = true")

    select "Русский", from: "Language"

    assert_selector "h1", text: "Настройки"
    within(".side-nav") { assert_link "Главная" }
    assert_equal "ru", evaluate_script("document.documentElement.lang")
    assert evaluate_script("window.__sameDocument === true")
    assert_equal "ru", @user.reload.lang

    select "English", from: "Язык"
    assert_selector "h1", text: "Settings"
  end

  test "contact links must be https" do
    visit "/app/settings/profile"

    fill_in "Telegram", with: "http://t.me/ada"
    assert_text "Use a link that starts with https://"
    assert_button "Save contacts", disabled: true

    fill_in "Telegram", with: "https://t.me/ada"
    fill_in "Slack", with: "https://ada.slack.com"
    click_button "Save contacts"

    assert_text "Saved"
    assert_equal({ "tg" => "https://t.me/ada", "slack" => "https://ada.slack.com" }, @user.reload.contact_links)
  end

  test "upload an avatar after previewing it" do
    visit "/app/settings/profile"
    upload = image_upload(format: "png", width: 300, height: 300)

    attach_file "Choose a photo", upload.path
    preview = find("img[alt='Preview of the new photo']")
    assert_match(/\Ablob:/, preview[:src])
    click_button "Upload photo"

    assert_text "Saved"
    assert_no_selector "img[alt='Preview of the new photo']"
    assert @user.reload.avatar.attached?
    assert_selector "img.avatar[src^='/files/']", minimum: 1
  end

  test "change the password with the current one" do
    visit "/app/settings/security"

    fill_in "Current password", with: "not my password"
    fill_in "New password", with: "a brand new passphrase"
    click_button "Change password"
    assert_invalid_field "Current password"
    assert @user.reload.authenticate(PASSWORD)

    fill_in "Current password", with: PASSWORD
    fill_in "New password", with: "a brand new passphrase"
    click_button "Change password"

    assert_text "Password changed. Other sessions were signed out."
    assert @user.reload.authenticate("a brand new passphrase")
  end

  # Spec web-client, "Connected apps screen" and "Password change warning".

  test "list connections: the client, the host claude.ai, read-write, and when it connected and was last active" do
    Oauth::AccessToken.create!(application: oauth_applications(:claude_ai), resource_owner_id: @user.id, scopes: "read write",
      expires_in: 3600, use_refresh_token: true)

    visit "/app/settings/connected-apps"

    within(".connections") do
      assert_text "Claude"
      assert_text "Redirects to claude.ai · Read and write"
      assert_text(/Connected .+ · last active .+/)
    end
    assert_selector "nav a[aria-current=page]", text: "Connected apps"
  end

  test "disconnect, after confirming" do
    access_token = Oauth::AccessToken.create!(application: oauth_applications(:claude_ai), resource_owner_id: @user.id, scopes: "read",
      expires_in: 3600, use_refresh_token: true)
    visit "/app/settings/connected-apps"

    click_button "Disconnect Claude"
    within("dialog") { click_button "Disconnect" }

    assert_text "“Claude” disconnected"
    assert_no_selector ".connections"
    assert access_token.reload.revoked?
  end

  test "no connections: how to connect an MCP client, instead of an empty list" do
    visit "/app/settings/connected-apps"

    assert_text "You have not connected any apps."
    assert_text "add Goalner's MCP address, #{Capybara.current_session.server.base_url}/mcp, as a connector"
    assert_link "How to connect an MCP client", href: "/docs/mcp"
    assert_no_selector ".connections"
  end

  test "password change warning: tokens are revoked and connected apps disconnected" do
    visit "/app/settings/security"

    assert_text "Changing your password revokes all your API tokens and disconnects all connected apps."
  end
end
