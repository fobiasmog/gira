require_relative "support"

# Spec mcp-server, "Tools for read-only connections"; add-mcp-oauth
# design.md, decision 9.
class McpScopesTest < McpIntegrationTest
  def access_token(scopes)
    Oauth::AccessToken.create!(application: oauth_applications(:claude_ai), resource_owner_id: users(:two).id, scopes: scopes,
      expires_in: 3600, use_refresh_token: true).plaintext_token
  end

  def tool_names(token)
    mcp_result("tools/list", token: token)["tools"].map { it["name"] }
  end

  def all_tools
    GoalnerMcp::ToolBuilder.new(nil).operations.map(&:id)
  end

  test "read-only connection lists tools: listTasks, not createTask" do
    names = tool_names(access_token("read"))

    assert_includes names, "listTasks"
    assert_not_includes names, "createTask"
    assert_equal GoalnerMcp::ToolBuilder.new(nil).operations.select(&:read_only?).map(&:id).sort, names.sort
  end

  test "read-only connection calls a write tool: insufficient_scope, and no API request beyond confirming the token" do
    token = access_token("read")

    assert_no_difference -> { Task.count } do
      result = mcp_result("tools/call", { name: "createTask", arguments: { project_id: projects(:goal).id, title: "Nope" } }, token: token)

      assert result["isError"]
      assert_match(/\Ainsufficient_scope: /, result.dig("content", 0, "text"))
    end
    assert_equal [ "POST /internal/mcp_token_exchange" ], api_requests
  end

  test "a read-only connection still calls read tools" do
    result = mcp_result("tools/call", { name: "listProjects", arguments: {} }, token: access_token("read"))

    assert_not result["isError"]
  end

  # Harden-mcp-oauth design.md, decision 11: the tools listed to read-only
  # connections, and those they may call, follow Operation#read_only?.
  test "the read-only hint and the tools a read-only connection may call come from one predicate" do
    builder = GoalnerMcp::ToolBuilder.new(nil)
    tools = builder.tools.index_by(&:name_value)
    read_only = Struct.new(:api_status) do
      def read_only_connection? = true
      def upstream_token = "glnr_stand_in"
    end.new
    api = Object.new
    api.define_singleton_method(:request) { |*, **| GoalnerMcp::ApiClient::Response.new(status: 204, body: "") }

    callable = builder.operations.reject do |operation|
      GoalnerMcp::ToolCall.new(api, operation).call(operation.path_parameters.to_h { [ it.to_sym, "1" ] }, read_only).error?
    end

    builder.operations.each do |operation|
      assert_equal operation.read_only?, tools.fetch(operation.id).annotations_value.read_only_hint, operation.id
    end
    assert_equal builder.operations.select(&:read_only?).map(&:id), callable.map(&:id)
    assert_equal tools.values.select { it.annotations_value.read_only_hint }.map(&:name_value), callable.map(&:id)
  end

  test "read-write connections and personal tokens list every tool" do
    assert_equal all_tools.sort, tool_names(access_token("read write")).sort
    assert_equal all_tools.sort, tool_names("glnr_two_goal_read").sort
  end
end
