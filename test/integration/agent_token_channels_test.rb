require "test_helper"

# Where an agent token works (spec agents, "Agent token channels"; add-agents
# design.md, decision 7). The MCP server sends its service key with every
# request it makes to the API; a direct request sends none.
class AgentTokenChannelsTest < ActionDispatch::IntegrationTest
  KEY = ApiTokenAuthentication::SERVICE_KEY_HEADER

  setup do
    @fish = create_agent(projects(:goal))
    @service_key = Rails.configuration.x.oauth.service_key
    @api_only = issue_agent_token(@fish, issuer: users(:two), channels: %w[api], name: "api")
    @mcp_only = issue_agent_token(@fish, issuer: users(:two), channels: %w[mcp], name: "mcp")
    @both = issue_agent_token(@fish, issuer: users(:two), channels: %w[api mcp], name: "both")
  end

  # A request with token and, when given, a service key.
  def request_me(token, key: nil)
    get api_me_path, headers: bearer(token).merge(key ? { KEY => key } : {})
  end

  def error_code
    response.parsed_body.dig("error", "code")
  end

  test "the test environment has a service key" do
    assert @service_key.present?
  end

  test "MCP-only token used directly: 401 invalid_token" do
    request_me @mcp_only

    assert_response :unauthorized
    assert_equal "invalid_token", error_code
  end

  test "MCP-only token through the MCP server: authenticated as the agent" do
    request_me @mcp_only, key: @service_key

    assert_response :success
    assert_equal @fish.user.id, response.parsed_body["id"]
  end

  test "forged service key: 401 invalid_service_key" do
    [ "made-up-key", "", @service_key + "x" ].each do |key|
      request_me @mcp_only, key: key

      assert_response :unauthorized
      assert_equal "invalid_service_key", error_code, key.inspect
    end
  end

  test "API-only token used directly: authenticated as the agent" do
    request_me @api_only

    assert_response :success
    assert_equal @fish.user.id, response.parsed_body["id"]
  end

  test "API-only token through the MCP server: 401 invalid_token" do
    request_me @api_only, key: @service_key

    assert_response :unauthorized
    assert_equal "invalid_token", error_code
  end

  test "API-only token with a wrong service key: 401 invalid_service_key" do
    request_me @api_only, key: "made-up-key"

    assert_response :unauthorized
    assert_equal "invalid_service_key", error_code
  end

  test "both channels: directly, through the MCP server, and with a wrong service key" do
    [ nil, @service_key, "made-up-key" ].each do |key|
      request_me @both, key: key

      assert_response :success, key.inspect
      assert_equal @fish.user.id, response.parsed_body["id"]
    end
  end

  test "the service key alone authenticates nothing" do
    get api_me_path, headers: { KEY => @service_key }

    assert_response :unauthorized
    assert_equal "unauthorized", error_code
  end

  test "personal tokens ignore the service key, right or wrong" do
    [ nil, @service_key, "made-up-key" ].each do |key|
      request_me "glnr_two_goal_read_write", key: key

      assert_response :success, key.inspect
    end
  end

  test "a refused request records no use and counts toward no limit" do
    request_me @mcp_only
    request_me @mcp_only, key: "made-up-key"

    assert_nil @fish.tokens.find_by!(name: "mcp").last_used_at
  end

  test "without a configured service key, no request counts as coming through MCP" do
    original = Rails.configuration.x.oauth.service_key
    Rails.configuration.x.oauth.service_key = nil

    request_me @mcp_only, key: ""
    assert_response :unauthorized
    assert_equal "invalid_service_key", error_code

    request_me @api_only
    assert_response :success
  ensure
    Rails.configuration.x.oauth.service_key = original
  end

  test "a file download answers a channel refusal with a bare 401" do
    avatar = @fish.user.avatar.blob.signed_id # fixture users have no avatar

    get file_path(avatar), headers: bearer(@mcp_only)
    assert_response :unauthorized
    assert_empty response.body

    get file_path(avatar), headers: bearer(@api_only)
    assert_response :success
  end
end
