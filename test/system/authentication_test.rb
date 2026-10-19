require "application_system_test_case"

class AuthenticationTest < ApplicationSystemTestCase
  PASSWORD = "correct horse battery"

  test "sign up, confirm through the email link, sign in and land on /app" do
    visit root_path
    click_link "Sign up", match: :first

    fill_in "Name", with: "Ada Lovelace"
    fill_in "Email", with: "ada@example.com"
    fill_in "Password", with: "analytical engine"
    click_button "Sign up"
    assert_text "Check your email to finish signing up."

    sign_in "ada@example.com", "analytical engine"
    assert_text "Please confirm your email address first."

    visit link_in(last_email_to("ada@example.com"), "/confirmations/")
    click_button "Confirm my email"
    assert_text "Your email address is confirmed."

    sign_in "ada@example.com", "analytical engine"
    assert_current_path %r{\A/app/?\z}  # the SPA normalizes /app to /app/
    assert_link "Dashboard"
  end

  test "public pages switch to Russian" do
    visit root_path
    click_on "RU"

    assert_text "Простой способ управления проектами"
    click_link "Войти"
    assert_selector "h1", text: "Вход"
  end

  test "lockout after ten wrong passwords, and unlock through the email link" do
    user = users(:one)
    10.times do
      sign_in user.email_address, "wrong password!"
      assert_text "Invalid email or password." # wait for each attempt to finish
    end

    travel 4.minutes # past the sign-in rate limit window, still inside the lock
    sign_in user.email_address, PASSWORD
    assert_text "Invalid email or password."

    visit link_in(last_email_to(user.email_address), "/unlocks/")
    click_button "Unlock my account"
    assert_text "Your account is unlocked."

    sign_in user.email_address, PASSWORD
    assert_current_path %r{\A/app/?\z}  # the SPA normalizes /app to /app/
  end

  test "reset a forgotten password" do
    user = users(:one)
    visit new_session_path
    click_on "Forgot password?"
    fill_in "Email", with: user.email_address
    click_button "Email reset instructions"
    assert_text "we sent a password reset link"

    visit link_in(last_email_to(user.email_address), "/passwords/")
    fill_in "Password", with: "a brand new password"
    fill_in "Repeat password", with: "a brand new password"
    click_button "Save password"
    assert_text "Your password has been changed."

    sign_in user.email_address, "a brand new password"
    assert_current_path %r{\A/app/?\z}  # the SPA normalizes /app to /app/
  end

  test "sign out" do
    sign_in users(:one).email_address, PASSWORD
    assert_current_path %r{\A/app/?\z}  # the SPA normalizes /app to /app/

    visit root_path
    click_button "Sign out"
    assert_link "Sign in" # the signed-out header

    visit app_path
    assert_current_path new_session_path
  end

  test "an idle session expires after 14 days" do
    sign_in users(:one).email_address, PASSWORD
    assert_current_path %r{\A/app/?\z}  # the SPA normalizes /app to /app/

    travel 15.days do
      visit app_path
      assert_current_path new_session_path
    end
  end
end
