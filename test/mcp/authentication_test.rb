require_relative "support"

# Authentication by personal API token (spec mcp-server, "Authentication by
# personal API token"; add-mcp-server design.md, decision 6). Fixture token
# values are "glnr_" followed by the fixture name.
class McpAuthenticationTest < McpIntegrationTest
  def assert_unauthorized(response, message = nil)
    assert_equal 401, response.status, message
    assert_match(/\ABearer\b/, response.headers["www-authenticate"], message)
    assert_not_includes response.body, "tools", message
  end

  test "no token: 401 with a Bearer challenge, and no tools are listed" do
    response = mcp_request("tools/list")

    assert_unauthorized response
    assert_equal %(Bearer resource_metadata="#{PUBLIC_URL}/.well-known/oauth-protected-resource/mcp", scope="read write"),
      response.headers["www-authenticate"]
    assert_empty api_requests
  end

  test "revoked token" do
    api_tokens(:two_goal_read_write).destroy! # User Two's token "CI"

    assert_unauthorized mcp_request("tools/list", token: "glnr_two_goal_read_write")
  end

  test "expired and unknown tokens" do
    assert_unauthorized mcp_request("tools/list", token: "glnr_two_goal_expired")
    assert_unauthorized mcp_request("tools/list", token: "glnr_unknown")
  end

  test "token in the query string" do
    post "/mcp?access_token=glnr_two_goal_read&token=glnr_two_goal_read",
      JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/list"),
      { "CONTENT_TYPE" => "application/json", "HTTP_ACCEPT" => "application/json", "HTTP_MCP_PROTOCOL_VERSION" => "2025-11-25" }

    assert_unauthorized last_response
    assert_empty api_requests
  end

  test "token in the request body" do
    response = mcp_request("tools/list", { token: "glnr_two_goal_read", _meta: { authorization: "Bearer glnr_two_goal_read" } })

    assert_unauthorized response
    assert_empty api_requests
  end

  test "other schemes, malformed Bearer values and other token shapes are refused without asking the API" do
    [ "Basic Z2xucjp4", "Bearer", "Bearer ", "Bearer a b", "glnr_two_goal_read", "Bearer not-a-goalner-token" ].each do |header|
      post "/mcp", JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/list"),
        { "CONTENT_TYPE" => "application/json", "HTTP_ACCEPT" => "application/json",
          "HTTP_MCP_PROTOCOL_VERSION" => "2025-11-25", "HTTP_AUTHORIZATION" => header }

      assert_unauthorized last_response, header
    end
    assert_empty api_requests
  end

  test "a valid token lists tools, and is checked with the API once while it is remembered" do
    2.times { assert_not_empty mcp_result("tools/list", token: "glnr_two_goal_read")["tools"] }

    assert_equal [ "GET /api/me" ], api_requests
  end

  test "token revoked between calls: the tool call gets 401, nothing changes, and the token is checked again" do
    assert_not_empty mcp_result("tools/list", token: "glnr_two_goal_read_write")["tools"]
    api_tokens(:two_goal_read_write).destroy!

    assert_no_difference -> { Task.count } do
      assert_unauthorized mcp_request("tools/call", { name: "createTask", arguments: { project_id: projects(:goal).id, title: "Late" } },
        token: "glnr_two_goal_read_write")
    end
    assert_unauthorized mcp_request("tools/list", token: "glnr_two_goal_read_write")
    assert_equal [ "GET /api/me", "POST /api/projects/#{projects(:goal).id}/tasks", "GET /api/me" ], api_requests
  end

  test "the API unavailable during the check: 503 with a generic message" do
    @api_transport.define_singleton_method(:call) { |*| raise Errno::ECONNREFUSED, "connect(2) for web:3000" }

    response = mcp_request("tools/list", token: "glnr_two_goal_read")

    assert_equal 503, response.status
    assert_equal "Goalner is unavailable. Try again later.", JSON.parse(response.body).dig("error", "message")
    assert_not_includes response.body, "web:3000"
  end

  test "the verified credential reaches the transport as an access token" do
    seen = nil
    authentication = GoalnerMcp::Authentication.new(
      ->(env) { seen = env["mcp.auth_info"]; [ 200, {}, [] ] },
      verifiers: [ GoalnerMcp::TokenVerifier.new(GoalnerMcp::ApiClient.new(@api_transport)) ],
      challenge: GoalnerMcp::Challenge.new(resource_metadata_url: "#{PUBLIC_URL}/.well-known/oauth-protected-resource/mcp")
    )

    authentication.call(Rack::MockRequest.env_for("/mcp", method: "POST", "HTTP_AUTHORIZATION" => "Bearer glnr_two_goal_read"))

    assert_kind_of MCP::Server::OAuth::AccessToken, seen
    assert_equal "glnr_two_goal_read", GoalnerMcp::UpstreamCredential.for(seen)
    assert_not_includes seen.inspect, "glnr_two_goal_read"
  end

  test "successes are remembered for 60 seconds, keyed by the token's digest" do
    now = 0
    cache = GoalnerMcp::LruCache.new(max_size: 10, ttl: 60, clock: -> { now })
    verifier = GoalnerMcp::TokenVerifier.new(GoalnerMcp::ApiClient.new(@api_transport), cache: cache)

    assert verifier.verify("glnr_two_goal_read")
    now = 59
    assert verifier.verify("glnr_two_goal_read")
    assert_equal 1, api_requests.size

    now = 61
    assert verifier.verify("glnr_two_goal_read")
    assert_equal 2, api_requests.size
    assert_equal [ Digest::SHA256.hexdigest("glnr_two_goal_read") ], cache.instance_variable_get(:@entries).keys
  end

  test "rejections are not remembered" do
    verifier = GoalnerMcp::TokenVerifier.new(GoalnerMcp::ApiClient.new(@api_transport))

    2.times { assert_nil verifier.verify("glnr_unknown") }
    assert_equal 2, api_requests.size
  end

  test "the cache keeps at most its size, dropping the least recently used" do
    cache = GoalnerMcp::LruCache.new(max_size: 2, ttl: 60)
    cache.write("a", 1)
    cache.write("b", 2)
    cache.read("a")
    cache.write("c", 3)

    assert_equal 2, cache.size
    assert_nil cache.read("b")
    assert_equal 1, cache.read("a")
  end
end
