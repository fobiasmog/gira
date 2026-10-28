require "test_helper"

class UserTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  PASSWORD = SessionTestHelper::PASSWORD

  def build_user(password)
    User.new(name: "Ada", email_address: "ada@example.com", password: password)
  end

  test "accepts a 12-character password" do
    assert build_user("a" * 12).valid?
  end

  test "rejects an 11-character password" do
    user = build_user("a" * 11)

    assert_not user.valid?
    assert user.errors.of_kind?(:password, :too_short)
  end

  test "rejects a password over 72 bytes" do
    user = build_user("a" * 73)

    assert_not user.valid?
    assert user.errors.added?(:password, :password_too_long)
  end

  test "downcases and strips email address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "rejects an unsupported language" do
    user = build_user("a" * 12)
    user.lang = "de"

    assert_not user.valid?
    assert user.errors.of_kind?(:lang, :inclusion)
  end

  # Re-entered passwords (design.md, decision 7)

  test "a re-entered password is refused while locked, and not counted" do
    user = users(:one)
    user.update_columns(failed_login_attempts: 10, locked_until: 30.minutes.from_now)

    assert_not user.verify_reentered_password(PASSWORD)
    assert_not user.verify_reentered_password("wrong password")
    assert_equal 10, user.reload.failed_login_attempts
    assert user.locked?
  end

  test "a wrong re-entered password is counted, and the tenth one locks and emails an unlock link" do
    user = users(:one)
    user.update_columns(failed_login_attempts: 8)

    assert_not user.verify_reentered_password("wrong password")
    assert_equal 9, user.reload.failed_login_attempts
    assert_not user.locked?

    assert_enqueued_email_with AccountMailer, :unlock, args: [ user ] do
      assert_not user.verify_reentered_password("wrong password")
    end
    assert user.reload.locked?
  end

  test "a correct re-entered password resets the count" do
    user = users(:one)
    user.update_columns(failed_login_attempts: 5)

    assert user.verify_reentered_password(PASSWORD)
    assert_equal 0, user.reload.failed_login_attempts
  end

  test "a password change deletes the user's API tokens, and a profile change keeps them" do
    user = users(:two)
    tokens = user.api_tokens.count
    assert_operator tokens, :>, 0

    user.update!(name: "Renamed", lang: "ru")
    assert_equal tokens, user.api_tokens.count

    user.update!(password: "a brand new password")
    assert_equal 0, user.api_tokens.count
    assert_operator ApiToken.where(user: users(:one)).count, :>, 0
  end
end
