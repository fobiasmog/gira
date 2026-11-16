require_relative "support"

# Agents' tokens at /mcp (spec mcp-server, "Agent tokens at the MCP
# endpoint"; spec agents, "Agent token channels"; add-agents design.md,
# decision 7). goal: one (owner) and two.
class McpAgentTokensTest < McpIntegrationTest
  SERVICE_KEY_HEADER = GoalnerMcp::ApiClient::SERVICE_KEY_HEADER

  setup do
    @goal = projects(:goal)
    @fish = create_agent(@goal, name: "Fish")
    @mcp_only = issue_agent_token(@fish, issuer: users(:two), channels: %w[mcp], name: "mcp")
    @api_only = issue_agent_token(@fish, issuer: users(:two), channels: %w[api], name: "api")
    @both = issue_agent_token(@fish, issuer: users(:two), channels: %w[api mcp], name: "both")
  end

  def call_tool(name, arguments = {}, token:)
    mcp_result("tools/call", { name: name, arguments: arguments }, token: token)
  end

  def text(result)
    result.fetch("content").sole.fetch("text")
  end

  # Makes the API expect another service key than the MCP server sends, as
  # when only one of the two has been given a new one.
  def with_api_service_key(key)
    original = Rails.configuration.x.oauth.service_key
    Rails.configuration.x.oauth.service_key = key
    yield
  ensure
    Rails.configuration.x.oauth.service_key = original
  end

  test "every API request carries the service key: the token check and the tool call" do
    result = call_tool("listProjects", token: @mcp_only)

    assert_not result["isError"], text(result)
    assert_equal [ "GET /api/me", "GET /api/projects" ], api_requests
    assert_equal [ Rails.configuration.x.oauth.service_key ] * 2, @api_transport.headers.map { |headers| headers[SERVICE_KEY_HEADER] }
  end

  test "without a service key the MCP server sends none" do
    client = GoalnerMcp::ApiClient.new(@api_transport)

    client.request("GET", "/api/me", token: "glnr_two_goal_read")

    assert_not @api_transport.headers.sole.key?(SERVICE_KEY_HEADER)
  end

  test "MCP token: a tool call acts as the agent" do
    result = call_tool("createTask", { project_id: @goal.id, title: "From Fish" }, token: @mcp_only)

    assert_not result["isError"], text(result)
    task = Task.find(JSON.parse(text(result)).fetch("id"))
    assert_equal [ "From Fish", @fish.user ], [ task.title, task.creator ]
  end

  test "an agent finds its work through the assigned view of listTasks" do
    mine = @goal.tasks.create!(title: "Fish's", creator: users(:one), assignee: @fish.user, status: statuses(:goal_todo))
    @goal.tasks.create!(title: "Bob's", creator: users(:one), assignee: users(:two), status: statuses(:goal_todo))

    result = call_tool("listTasks", { project_id: @goal.id, view: "assigned" }, token: @mcp_only)

    assert_not result["isError"], text(result)
    assert_equal [ mine.id ], JSON.parse(text(result)).map { |card| card["id"] }
  end

  test "API-only token: 401 with a Bearer challenge, and no tools are listed" do
    response = mcp_request("tools/list", token: @api_only)

    assert_equal 401, response.status
    assert_equal "invalid_token", challenge_parameters(response)["error"]
    assert_not_includes response.body, "tools"
  end

  test "a token for both channels works at /mcp" do
    assert mcp_result("tools/list", token: @both).fetch("tools").any?
  end

  test "personal tokens unchanged: the tools are listed" do
    assert mcp_result("tools/list", token: "glnr_two_goal_read_write").fetch("tools").any?
  end

  # A refused service key is the MCP server's trouble, not the token's.

  test "service key refused: 503 that Goalner is unavailable, without invalid_token" do
    @app = build_app(service_key: "not-the-api's-key")

    response = mcp_request("tools/list", token: @mcp_only)

    assert_equal 503, response.status
    assert_equal GoalnerMcp::ApiClient::UNAVAILABLE_MESSAGE, JSON.parse(response.body).dig("error", "message")
    assert_nil response.headers["www-authenticate"]
    assert_not_includes response.body, "invalid_token"
    assert_not_includes response.body, "tools"
  end

  test "service key refused for an API-only token: 503 too, as the API cannot tell where the request came from" do
    @app = build_app(service_key: "not-the-api's-key")

    assert_equal 503, mcp_request("tools/list", token: @api_only).status
  end

  test "service key refused during a tool call: an unavailable tool error, not a 401" do
    assert mcp_result("tools/list", token: @mcp_only).fetch("tools").any?

    with_api_service_key("a-new-key-the-mcp-server-does-not-have") do
      assert_no_difference -> { Task.count } do
        result = call_tool("createTask", { project_id: @goal.id, title: "Lost" }, token: @mcp_only)

        assert result["isError"]
        assert_equal GoalnerMcp::ApiClient::UNAVAILABLE_MESSAGE, text(result)
      end
    end

    # Once both have the same key again, the same token keeps working.
    assert_not call_tool("listProjects", token: @mcp_only)["isError"]
  end

  test "a refused service key does not take down personal tokens or tokens for both channels" do
    @app = build_app(service_key: "not-the-api's-key")

    [ "glnr_two_goal_read_write", @both ].each do |token|
      assert mcp_result("tools/list", token: token).fetch("tools").any?
      assert_not call_tool("listProjects", token: token)["isError"]
    end
  end

  test "the refusal is logged without the key or the token" do
    output = StringIO.new
    original = GoalnerMcp.logger
    GoalnerMcp.logger = Logger.new(output)
    @app = build_app(service_key: "not-the-api's-key")

    mcp_request("tools/list", token: @mcp_only)

    assert_includes output.string, "check MCP_SERVICE_KEY"
    assert_not_includes output.string, "not-the-api's-key"
    assert_not_includes output.string, @mcp_only
  ensure
    GoalnerMcp.logger = original
  end

  test "error codes are read from the API's envelope and from the exchange's answer" do
    assert_equal "invalid_token", GoalnerMcp::ApiClient.error_code(JSON.generate(error: { code: "invalid_token", message: "…" }))
    assert_equal "invalid_service_key", GoalnerMcp::ApiClient.error_code(JSON.generate(error: "invalid_service_key"))
    [ "", "<html>Bad gateway</html>", "[]", "null", JSON.generate(error: nil) ].each do |body|
      assert_nil GoalnerMcp::ApiClient.error_code(body), body
    end
  end

  test "a deleted agent's token: 401" do
    @fish.delete!

    assert_equal 401, mcp_request("tools/list", token: @mcp_only).status
  end
end
