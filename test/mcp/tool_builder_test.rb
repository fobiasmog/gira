require_relative "support"

# Tools generated from docs/openapi.yaml (spec mcp-server, "Tools follow the
# API document" and "Tool hints"; add-mcp-server design.md, decisions 4 and 5).
class McpToolBuilderTest < McpIntegrationTest
  DOCUMENT = YAML.safe_load_file(Rails.root.join("docs/openapi.yaml"))

  def default_token
    "glnr_two_goal_read"
  end

  # The operations whose success response is JSON or empty, read from the
  # document independently of ToolBuilder.
  def json_operation_ids(document = DOCUMENT)
    document["paths"].values.flat_map do |item|
      item.slice("get", "post", "put", "patch", "delete").values.filter_map do |operation|
        _status, success = operation["responses"].find { |status, _| status.start_with?("2") }
        operation["operationId"] if success["content"].nil? || success["content"].key?("application/json")
      end
    end
  end

  def build(document)
    GoalnerMcp::ToolBuilder.new(nil, document: document).tools
  end

  def listed_tools
    mcp_result("tools/list")["tools"].index_by { it["name"] }
  end

  test "one tool per JSON operation of the document, and no file downloads" do
    names = listed_tools.keys

    assert_equal json_operation_ids.sort, names.sort
    assert_equal 35, names.size
    assert_not_includes names, "downloadFile"
    assert_not_includes names, "downloadFilePreview"
  end

  test "create task tool: required and optional arguments, title and description" do
    tool = listed_tools.fetch("createTask")
    schema = tool["inputSchema"]
    body_fields = DOCUMENT.dig("components", "schemas", "TaskCreate", "properties").keys

    assert_equal %w[ project_id title ], schema["required"]
    assert_equal [ "project_id", *body_fields ].sort, schema["properties"].keys.sort
    assert_includes body_fields, "description"
    assert_includes body_fields, "status_id"
    assert_equal "Create a task", tool["title"]
    assert_match(/\ACreate a task\n\nA task created with a column/, tool["description"])
    assert tool["description"].end_with?("POST /api/projects/{project_id}/tasks")
  end

  test "path parameters declared on the path are required arguments too" do
    schema = listed_tools.fetch("showTask")["inputSchema"]

    assert_equal %w[ project_id id ], schema["required"]
    assert_equal "The task's id, or its key such as `GOAL-12`.", schema.dig("properties", "id", "description")
  end

  test "every input schema is self-contained" do
    listed_tools.each_value do |tool|
      assert_not_includes JSON.generate(tool["inputSchema"]), "$ref", tool["name"]
      assert_not_includes JSON.generate(tool["inputSchema"]), "allOf", tool["name"]
    end
  end

  test "document changes: an added operation adds a tool" do
    document = DOCUMENT.deep_dup
    document["paths"]["/api/projects/{project_id}/statuses"]["post"] = {
      "operationId" => "createColumn", "summary" => "Add a column",
      "parameters" => [ { "$ref" => "#/components/parameters/ProjectId" } ],
      "requestBody" => { "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "title" => { "type" => "string" } } } } } },
      "responses" => { "201" => { "description" => "The column.", "content" => { "application/json" => { "schema" => { "$ref" => "#/components/schemas/Column" } } } } }
    }

    tools = build(document)

    assert_equal json_operation_ids.size + 1, tools.size
    assert_equal %w[ project_id title ], tools.find { it.name_value == "createColumn" }.input_schema_value.to_h[:properties].keys.map(&:to_s)
  end

  test "document changes: a removed operation removes its tool" do
    document = DOCUMENT.deep_dup
    document["paths"]["/api/comments/{id}"].delete("delete")

    assert_not_includes build(document).map(&:name_value), "deleteComment"
  end

  test "a parameter and a body property with the same name fail the build, naming both" do
    document = DOCUMENT.deep_dup
    document.dig("components", "schemas", "TaskCreate", "properties")["project_id"] = { "type" => "integer" }

    error = assert_raises(GoalnerMcp::ToolBuilder::Error) { build(document) }
    assert_match(/createTask/, error.message)
    assert_match(/project_id/, error.message)
  end

  test "read tool" do
    annotations = listed_tools.fetch("listTasks")["annotations"]

    assert_equal true, annotations["readOnlyHint"]
    assert_nil annotations["destructiveHint"]
    assert_nil annotations["idempotentHint"]
  end

  test "deleting tool" do
    tools = listed_tools

    %w[ archiveTask deleteComment ].each do |name|
      assert_equal true, tools.fetch(name)["annotations"]["destructiveHint"], name
      assert_equal false, tools.fetch(name)["annotations"]["readOnlyHint"], name
    end
    assert_equal false, tools.fetch("createTask")["annotations"]["destructiveHint"]
    assert_equal false, tools.fetch("createTask")["annotations"]["readOnlyHint"]
    assert_equal true, tools.fetch("placeTask")["annotations"]["idempotentHint"]
  end

  test "every tool acts only within Goalner" do
    listed_tools.each_value { |tool| assert_equal false, tool["annotations"]["openWorldHint"], tool["name"] }
  end
end
