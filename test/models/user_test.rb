require "test_helper"

class UserTest < ActiveSupport::TestCase
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
end
