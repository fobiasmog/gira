require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  def issue(**attributes)
    ApiToken.issue(user: users(:two), project: projects(:goal), name: "CI", access: "read_write", expires_in_days: 90, **attributes)
  end

  test "the value has the glnr_ prefix and 40 base58 characters" do
    token = issue

    assert_match(/\Aglnr_[1-9A-HJ-NP-Za-km-z]{40}\z/, token.value)
    assert_not_equal issue.value, token.value
  end

  test "the stored row contains neither the value nor anything that authenticates" do
    token = issue.tap(&:save!)
    stored = ApiToken.connection.select_one("SELECT * FROM api_tokens WHERE id = #{token.id}").values.map(&:to_s)

    assert_equal token.value.last(4), token.last_characters
    assert_not stored.any? { |column| column.include?(token.value) || column.include?(token.value.delete_prefix("glnr_")) }
    stored.each { |column| assert_nil ApiToken.find_active_by_value(column), "a stored column authenticates" }
  end

  test "lookup by value" do
    token = issue.tap(&:save!)

    assert_equal token, ApiToken.find_active_by_value(token.value)
    assert_nil ApiToken.find_active_by_value(token.value + "x")
    assert_nil ApiToken.find_active_by_value(nil)
    assert_nil ApiToken.find_active_by_value("")
  end

  test "an expired token is not found" do
    token = issue(expires_in_days: 1).tap(&:save!)

    travel 1.day + 1.second do
      assert_nil ApiToken.find_active_by_value(token.value)
    end
    assert_nil ApiToken.find_active_by_value("glnr_two_goal_expired")
  end

  test "expiry is 1 to 365 days after creation, and required" do
    freeze_time do
      assert_equal 1.day.from_now, issue(expires_in_days: 1).tap(&:save!).expires_at
      assert_equal 365.days.from_now, issue(expires_in_days: 365).tap(&:save!).expires_at
    end

    [ 0, 366, nil, "", 1.5, "soon" ].each do |days|
      token = issue(expires_in_days: days)
      assert_not token.valid?, days.inspect
      assert token.errors.key?(:expires_in_days), days.inspect
    end
  end

  test "name is 1 to 100 characters" do
    assert issue(name: "a" * 100).valid?
    assert_not issue(name: "").valid?
    assert_not issue(name: "a" * 101).valid?
  end

  test "access is read or read_write" do
    assert issue(access: "read").valid?
    assert_not issue(access: "admin").valid?
    assert_not issue(access: nil).valid?
  end

  test "last use is written at most once an hour" do
    token = api_tokens(:two_goal_read_write)

    freeze_time do
      token.touch_last_used!
      assert_equal Time.current, token.reload.last_used_at
    end

    first_use = token.last_used_at
    travel 59.minutes do
      token.touch_last_used!
      assert_equal first_use, token.reload.last_used_at
    end

    travel 61.minutes do
      token.touch_last_used!
      assert_operator token.reload.last_used_at, :>, first_use
    end
  end

  test "the database requires exactly one of a project and an access token" do
    _connection_token, access_token = create_connection_token(users(:two))
    token = issue.tap(&:save!)

    assert_raises(ActiveRecord::StatementInvalid) { token.update_column(:oauth_access_token_id, access_token.id) }
    assert_raises(ActiveRecord::StatementInvalid) { ApiToken.where(id: token.id).update_all(project_id: nil) }
  end

  test "a connection token: named after the client, with the connection's access, expiring with its access token" do
    connection_token, access_token = create_connection_token(users(:two), scopes: "read")

    assert connection_token.connection?
    assert_nil connection_token.project
    assert_equal [ "Claude", "read", users(:two) ], [ connection_token.name, connection_token.access, connection_token.user ]
    assert_in_delta access_token.expires_at, connection_token.expires_at, 1
    assert_equal "read_write", create_connection_token(users(:two)).first.access
    assert_match(/\Aglnr_/, connection_token.value)
  end

  test "personal and connection scopes" do
    connection_token, = create_connection_token(users(:two))

    assert_includes ApiToken.of_connections, connection_token
    assert_not_includes ApiToken.personal, connection_token
    assert_includes ApiToken.personal, api_tokens(:two_goal_read)
  end

  test "a user's tokens are personal ones, and of_connections replaces personal with the user's connection tokens" do
    connection_token, = create_connection_token(users(:two))
    create_connection_token(users(:one))

    assert_not_includes users(:two).api_tokens, connection_token
    assert_includes users(:two).api_tokens, api_tokens(:two_goal_read)
    assert_equal [ connection_token ], users(:two).api_tokens.of_connections.to_a
    assert_equal [ connection_token ], ApiToken.personal.of_connections.where(user: users(:two)).to_a
  end

  test "a personal token still needs a project and an expiry" do
    assert_not issue(project: nil).valid?
    assert_not issue(expires_in_days: nil).valid?
  end
end
