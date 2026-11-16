require_relative "support"
require "capybara"

# The MCP server's own transport, Net::HTTP over a socket, against this
# test's Rails application served by Puma. The other MCP tests use
# RackTransport, which hands back Rack's UTF-8 strings; only here does a body
# arrive the way Net::HTTP reads it, tagged binary when it holds a non-ASCII
# byte.
class McpHttpTransportTest < McpIntegrationTest
  TITLE = "Сдать 7.2 – adopt the cards…"

  setup do
    Capybara.server = :puma, { Silent: true }
    api = Capybara::Server.new(Rails.application).boot
    @api_transport = GoalnerMcp::ApiClient::HttpTransport.new("http://#{api.host}:#{api.port}")
    @goal = projects(:goal)
    @task = @goal.tasks.create!(title: TITLE, creator: users(:two), status: @goal.first_status)
  end

  def default_token
    "glnr_two_goal_read_write"
  end

  def call_tool(name, arguments)
    result = mcp_result("tools/call", { name: name, arguments: arguments })
    text = result.fetch("content").sole.fetch("text")
    assert_not result["isError"], text
    JSON.parse(text)
  end

  test "a read whose answer holds non-ASCII text" do
    task = call_tool("showTask", { project_id: @goal.id, id: @task.key })

    assert_equal TITLE, task["title"]
  end

  test "a write whose answer holds non-ASCII text succeeds, once" do
    assert_difference -> { @task.comments.count }, 1 do
      comment = call_tool("createComment", { project_id: @goal.id, task_id: @task.id, body: "Готово – done…" })

      assert_equal "Готово – done…", comment["body"]
    end
  end

  test "an ASCII answer is unchanged" do
    @task.update!(title: "Adopt the cards...")

    assert_equal "Adopt the cards...", call_tool("showTask", { project_id: @goal.id, id: @task.key })["title"]
  end
end
