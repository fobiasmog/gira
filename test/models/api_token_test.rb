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

  # Agent tokens (spec agents, "Issue agent tokens"; add-agents design.md, decision 5)

  def issue_for_agent(agent, **attributes)
    ApiToken.issue_for_agent(agent, issuer: users(:two), name: "runner", access: "read_write", channels: %w[api mcp], **attributes)
  end

  test "an agent token belongs to the agent, names its issuer, and has no project and no expiry" do
    agent = create_agent(projects(:goal))
    token = issue_for_agent(agent).tap(&:save!)

    assert_equal agent.user, token.user
    assert_equal users(:two), token.issuer
    assert_nil token.project_id
    assert_nil token.expires_at
    assert_match(/\Aglnr_[1-9A-HJ-NP-Za-km-z]{40}\z/, token.value)
    assert token.agent?
    assert_not token.personal?
    assert_not token.connection?
  end

  test "an agent token is not a personal token of the agent or of its issuer" do
    agent = create_agent(projects(:goal))
    token = issue_for_agent(agent).tap(&:save!)

    assert_not_includes ApiToken.personal, token
    assert_not_includes ApiToken.of_connections, token
    assert_includes ApiToken.of_agents, token
    assert_equal [ token ], agent.tokens.to_a
    assert_empty agent.user.api_tokens
    assert_not_includes users(:two).api_tokens, token
    assert_equal [ token ], agent.user.api_tokens.of_agents.to_a
  end

  test "agent tokens do not count toward their issuer's personal tokens" do
    agent = create_agent(projects(:goal))

    assert_no_difference -> { users(:two).api_tokens.active.count } do
      issue_for_agent(agent).save!
    end
  end

  test "an agent token never expires and is found by its value" do
    agent = create_agent(projects(:goal))
    token = issue_for_agent(agent).tap(&:save!)

    travel 400.days do
      assert_includes ApiToken.active, token
      assert_not_includes ApiToken.expired, token
      assert_equal token, ApiToken.find_active_by_value(token.value)
    end
  end

  test "personal and connection tokens keep their kinds" do
    personal = api_tokens(:two_goal_read_write)
    connection, _access_token = create_connection_token(users(:two))

    assert personal.personal?
    assert_not personal.agent?
    assert connection.connection?
    assert_not connection.personal?
    assert_not connection.agent?
    assert_includes ApiToken.personal, personal
    assert_not_includes ApiToken.personal, connection
    assert_equal [ connection ], users(:two).api_tokens.of_connections.to_a
  end

  test "channels are the API, MCP or both" do
    agent = create_agent(projects(:goal))

    { %w[api] => "api", %w[mcp] => "mcp", %w[mcp api] => "api_mcp", %w[api api] => "api" }.each do |given, stored|
      token = issue_for_agent(agent, channels: given)

      assert token.valid?, given.inspect
      assert_equal stored, token.channels
    end
    assert_equal %w[api mcp], issue_for_agent(agent).channel_list
    assert issue_for_agent(agent, channels: %w[mcp]).channel?("mcp")
    assert_not issue_for_agent(agent, channels: %w[mcp]).channel?("api")
  end

  test "unknown or missing channels are rejected" do
    agent = create_agent(projects(:goal))

    [ nil, [], %w[ftp], %w[api ftp], "api_mcp_ftp" ].each do |given|
      token = issue_for_agent(agent, channels: given)

      assert_not token.valid?, given.inspect
      assert token.errors.of_kind?(:channels, :inclusion)
    end
  end

  test "only an agent token for one channel is single-channel" do
    agent = create_agent(projects(:goal))

    assert issue_for_agent(agent, channels: %w[api]).single_channel?
    assert issue_for_agent(agent, channels: %w[mcp]).single_channel?
    assert_not issue_for_agent(agent).single_channel?
    assert_not api_tokens(:two_goal_read_write).single_channel?
  end

  test "an agent has at most 20 live tokens, whoever issued them" do
    agent = create_agent(projects(:goal))
    10.times { issue_for_agent(agent).save! }
    10.times { issue_for_agent(agent, issuer: users(:one)).save! }

    token = issue_for_agent(agent)

    assert_not token.save
    assert token.errors.of_kind?(:base, :too_many_for_agent)
    assert_equal 20, agent.tokens.count

    other = create_agent(projects(:goal), name: "Owl")
    assert issue_for_agent(other).save
  end

  test "the database rejects a row that mixes kinds" do
    agent = create_agent(projects(:goal))
    token = issue_for_agent(agent).tap(&:save!)

    [
      -> { token.update_columns(project_id: projects(:goal).id) },
      -> { token.update_columns(expires_at: 1.day.from_now) },
      -> { token.update_columns(channels: nil) },
      -> { token.update_columns(channels: "ftp") },
      -> { api_tokens(:two_goal_read_write).update_columns(expires_at: nil) },
      -> { api_tokens(:two_goal_read_write).update_columns(issuer_id: users(:one).id) },
      -> { api_tokens(:two_goal_read_write).update_columns(channels: "api") }
    ].each do |change|
      assert_raises(ActiveRecord::StatementInvalid) { ApiToken.transaction(requires_new: true) { change.call } }
    end
  end
end
