require_relative "support"

# OpenSpec changes and task keys through MCP (spec openspec-changes, "Import
# a change"; spec tasks, "Name a task by id or key in every task request";
# add-openspec-changes design.md, decisions 7 and 8). The tools come from
# docs/openapi.yaml with no MCP code of their own.
class McpOpenspecToolsTest < McpIntegrationTest
  TEXT = "## 1. Model\n\n- [ ] 1.1 Add the table\n- [ ] 1.2 Add the model\n"

  def default_token
    "glnr_two_goal_read_write"
  end

  def listed_tools(token: default_token)
    mcp_result("tools/list", token: token)["tools"].index_by { it["name"] }
  end

  def call_tool(name, arguments = {}, token: default_token)
    mcp_result("tools/call", { name: name, arguments: arguments }, token: token)
  end

  def text(result) = result.fetch("content").sole.fetch("text")

  def read_only_connection
    Oauth::AccessToken.create!(application: oauth_applications(:claude_ai), resource_owner_id: users(:two).id, scopes: "read",
      expires_in: 3600, use_refresh_token: true).plaintext_token
  end

  test "importOpenspecChange is a write tool, showOpenspecChange a read-only one" do
    tools = listed_tools

    assert_equal false, tools.fetch("importOpenspecChange").dig("annotations", "readOnlyHint")
    assert_equal false, tools.fetch("importOpenspecChange").dig("annotations", "destructiveHint")
    assert_equal true, tools.fetch("showOpenspecChange").dig("annotations", "readOnlyHint")
    assert_equal %w[ project_id name artifacts ], tools.fetch("importOpenspecChange").dig("inputSchema", "required")
    assert_match(/How an agent works through a change/, tools.fetch("importOpenspecChange")["description"])
  end

  test "a read-only connection sees only showOpenspecChange" do
    names = listed_tools(token: read_only_connection).keys

    assert_includes names, "showOpenspecChange"
    assert_not_includes names, "importOpenspecChange"
  end

  test "import and show through MCP" do
    result = call_tool("importOpenspecChange", { project_id: projects(:goal).id, name: "add-labels", artifacts: { tasks: TEXT } })

    assert_not result["isError"], text(result)
    body = JSON.parse(text(result))
    assert_equal [ "add-labels: 1. Model" ], body["cards"].map { it["title"] }
    assert_equal users(:two), projects(:goal).openspec_changes.find_by!(name: "add-labels").imported_by

    shown = call_tool("showOpenspecChange", { project_id: projects(:goal).id, name: "add-labels" })
    assert_equal body["tasks"], JSON.parse(text(shown))["tasks"]
  end

  test "completeSubtask takes the key from a mark, and still takes an id" do
    change = OpenspecChange::Import.new(project: projects(:goal), user: users(:two), name: "add-labels", artifacts: { "tasks" => TEXT }).run!.change
    table, model = change.tasks.where.not(parent_id: nil).order(:id).to_a
    key = change.tasks_text[/1\.1 Add the table <!-- goalner:(GOAL-\d+) -->/, 1]
    assert_equal table.key, key

    by_key = call_tool("completeSubtask", { project_id: projects(:goal).id, task_id: key })
    by_id = call_tool("completeSubtask", { project_id: projects(:goal).id, task_id: model.id })

    assert_not by_key["isError"], text(by_key)
    assert_not by_id["isError"], text(by_id)
    assert table.reload.done?
    assert model.reload.done?
  end

  test "a malformed task_id is refused before any request" do
    result = call_tool("completeSubtask", { project_id: projects(:goal).id, task_id: "not a key" })

    assert result["isError"]
    assert_equal [ "GET /api/me" ], api_requests
  end
end
