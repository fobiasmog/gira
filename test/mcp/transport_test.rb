require_relative "support"

# The stateless JSON transport (spec mcp-server, "MCP endpoint" and "Browser
# origins"; add-mcp-server design.md, decision 3).
class McpTransportTest < McpIntegrationTest
  def default_token
    "glnr_two_goal_read"
  end

  test "a tools list is one JSON response without a session id" do
    response = mcp_request("tools/list")

    assert_equal 200, response.status
    assert_equal "application/json", response.media_type
    assert_nil response.headers["mcp-session-id"]
    assert_not_empty JSON.parse(response.body).dig("result", "tools")
  end

  test "an initialize issues no session id either" do
    response = mcp_request("initialize", { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "test", version: "1" } })

    assert_equal 200, response.status
    assert_nil response.headers["mcp-session-id"]
  end

  test "a 2026-07-28 request needs no initialize" do
    meta = { "io.modelcontextprotocol/protocolVersion": "2026-07-28",
             "io.modelcontextprotocol/clientInfo": { name: "test", version: "1" },
             "io.modelcontextprotocol/clientCapabilities": {} }
    response = mcp_request("tools/list", { _meta: meta }, headers: { "HTTP_MCP_PROTOCOL_VERSION" => "2026-07-28", "HTTP_MCP_METHOD" => "tools/list" })

    assert_equal 200, response.status
    assert_equal "application/json", response.media_type
    assert_nil response.headers["mcp-session-id"]
  end

  test "consecutive requests on different instances" do
    other_instance = build_app

    assert_not_empty mcp_result("tools/list")["tools"]
    @app = other_instance
    assert_not mcp_result("tools/call", { name: "listProjects", arguments: {} })["isError"]
  end

  test "stream requests and every method other than POST answer 405" do
    %w[ GET DELETE PUT ].each do |method|
      custom_request method, "/mcp", {}, { "HTTP_ACCEPT" => "text/event-stream", "HTTP_MCP_PROTOCOL_VERSION" => "2025-11-25" }

      assert_equal 405, last_response.status, method
      assert_equal "POST", last_response.headers["allow"]
    end
  end

  test "a foreign origin is refused and changes nothing" do
    arguments = { project_id: projects(:goal).id, title: "Forged" }

    assert_no_difference -> { Task.count } do
      response = mcp_request("tools/call", { name: "createTask", arguments: arguments },
        token: "glnr_two_goal_read_write", headers: { "HTTP_ORIGIN" => "https://evil.example" })

      assert_equal 403, response.status
      assert_nil JSON.parse(response.body)["result"]
    end
  end

  test "the application's own origin and native clients are served" do
    assert_equal 200, mcp_request("tools/list", headers: { "HTTP_ORIGIN" => PUBLIC_URL }).status
    assert_equal 200, mcp_request("tools/list").status
  end
end
