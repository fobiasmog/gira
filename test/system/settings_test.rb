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
end
