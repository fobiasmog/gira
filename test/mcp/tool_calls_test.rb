require_relative "support"

# Tool calls become one API request each, made with the caller's token (spec
# mcp-server, "Tool calls act as the token", "Tool arguments", "Tool results"
# and "Tool errors"; add-mcp-server design.md, decisions 4 and 8). Fixture
# token values are "glnr_" followed by the fixture name; two is a member of
# goal and side.
class McpToolCallsTest < McpIntegrationTest
  setup do
    @goal = projects(:goal)
    @side = projects(:side)
  end

  def default_token
    "glnr_two_goal_read_write"
  end

  def create_task(project = @goal, **attributes)
    project.tasks.create!(title: "Task", creator: users(:two), status: project.first_status, **attributes)
  end

  def call_tool(name, arguments = {}, token: default_token)
    mcp_result("tools/call", { name: name, arguments: arguments }, token: token)
  end

  def text(result)
    result.fetch("content").sole.fetch("text")
  end

  # API requests made after the token check.
  def tool_requests
    api_requests - [ "GET /api/me" ]
  end

  test "partial update" do
    task = create_task(description: "Keep me", important: true, assignee: users(:one))

    result = call_tool("updateTask", { project_id: @goal.id, id: task.id.to_s, title: "Renamed" })

    assert_not result["isError"], text(result)
    task.reload
    assert_equal [ "Renamed", "Keep me", true, users(:one) ], [ task.title, task.description, task.important, task.assignee ]
    assert_equal [ "PATCH /api/projects/#{@goal.id}/tasks/#{task.id}" ], tool_requests
  end

  test "explicit null" do
    sprint = @goal.sprints.create!(title: "Week 1", starts_on: Date.current, ends_on: 1.week.from_now)
    task = create_task(sprint: sprint)

    result = call_tool("setTaskSprint", { project_id: @goal.id, task_id: task.id, sprint_id: nil })

    assert_not result["isError"], text(result)
    assert_nil task.reload.sprint
  end

  test "task key as id" do
    task = create_task(number: 12, title: "Twelve")

    result = call_tool("showTask", { project_id: @goal.id, id: "GOAL-12" })

    assert_equal [ task.id, "GOAL-12", "Twelve" ], JSON.parse(text(result)).values_at("id", "key", "title")
    assert_equal [ "GET /api/projects/#{@goal.id}/tasks/GOAL-12" ], tool_requests
  end

  test "path parameters are URL-encoded and query parameters are sent only when given" do
    call_tool("showTask", { project_id: @goal.id, id: "GOAL-1" })
    call_tool("listTasks", { project_id: @goal.id })
    call_tool("listTasks", { project_id: @goal.id, view: "backlog" })

    assert_equal [ "GET /api/projects/#{@goal.id}/tasks/GOAL-1", "GET /api/projects/#{@goal.id}/tasks",
                   "GET /api/projects/#{@goal.id}/tasks?view=backlog" ], tool_requests
  end

  test "missing required argument" do
    assert_no_difference -> { Task.count } do
      result = call_tool("createTask", { project_id: @goal.id })

      assert result["isError"]
      assert_match(/\btitle\b/, text(result))
    end
    assert_empty tool_requests
  end

  test "arguments of the wrong type or unknown names are refused before any request" do
    [ { project_id: "GOAL", title: "x" }, { project_id: @goal.id, title: "x", priority: "high" } ].each do |arguments|
      result = call_tool("createTask", arguments)

      assert result["isError"], arguments.inspect
    end
    assert_empty tool_requests
  end

  test "show task: the result is the API's response body" do
    task = create_task(description: "Details")

    result = call_tool("showTask", { project_id: @goal.id, id: task.id.to_s })

    api_response = Rack::MockRequest.new(Rails.application).get("/api/projects/#{@goal.id}/tasks/#{task.id}",
      "HTTP_AUTHORIZATION" => "Bearer glnr_two_goal_read_write")
    assert_not result["isError"]
    assert_equal JSON.parse(api_response.body), JSON.parse(text(result))
  end

  test "no content" do
    task = create_task

    result = call_tool("archiveTask", { project_id: @goal.id, id: task.id.to_s })

    assert_not result["isError"]
    assert_equal "Done.", text(result)
    assert task.reload.archived?
  end

  test "validation error: the code, the message and each field message" do
    @goal.labels.create!(title: "Bug")

    result = call_tool("createLabel", { project_id: @goal.id, title: "bug" })

    assert result["isError"]
    code_line, *field_lines = text(result).lines(chomp: true)
    assert_equal "validation_failed: Some fields are invalid.", code_line
    assert_not_empty field_lines
    assert field_lines.all? { it.start_with?("title: ") }, field_lines.inspect
  end

  test "attribution" do
    result = nil
    assert_difference -> { @goal.tasks.count }, 1 do
      result = call_tool("createTask", { project_id: @goal.id, title: "From an assistant" })
    end

    assert_not result["isError"], text(result)
    assert_equal users(:two), @goal.tasks.find_by!(title: "From an assistant").creator
  end

  test "read-only token writes" do
    assert_no_difference -> { Task.count } do
      result = call_tool("createTask", { project_id: @goal.id, title: "Nope" }, token: "glnr_two_goal_read")

      assert result["isError"]
      assert_match(/\Ainsufficient_scope: /, text(result))
    end
  end

  test "another project of the owner" do
    create_task(@side)

    result = call_tool("listTasks", { project_id: @side.id })

    assert result["isError"]
    assert_equal "not_found: Not found.", text(result)
  end

  test "rate limit" do
    ApiTokenAuthentication::REQUESTS_PER_MINUTE.times do
      Rack::MockRequest.new(Rails.application).get("/api/projects/#{@goal.id}/board", "HTTP_AUTHORIZATION" => "Bearer #{default_token}")
    end

    assert_no_difference -> { Task.count } do
      result = call_tool("createTask", { project_id: @goal.id, title: "Too many" })

      assert result["isError"]
      assert_match(/\Arate_limited: /, text(result))
    end
  end

  test "API unavailable: a generic message, whatever went wrong" do
    task = create_task
    assert_not_empty mcp_result("tools/list")["tools"]

    [ -> { raise Errno::ECONNREFUSED, "connect(2) for 10.0.0.5:3000" },
      -> { [ 302, "" ] },
      -> { [ 503, "<html>Bad gateway from web-1</html>" ] } ].each do |failure|
      @api_transport.define_singleton_method(:call) { |*| failure.call }

      result = call_tool("showTask", { project_id: @goal.id, id: task.id.to_s })

      assert result["isError"]
      assert_equal "Goalner is unavailable. Try again later.", text(result)
    end
  end
end
