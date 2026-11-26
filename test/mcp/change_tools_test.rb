require_relative "support"

# Changes, OpenSpec imports and task keys through MCP (spec changes; spec
# openspec-changes, "Import a change" and "Files of a change"; spec comments,
# "Comment on a change"; spec tasks, "Name a task by id or key in every task
# request"; replace-sprints-with-changes design.md, decision 5;
# add-change-conversation design.md, decision 9). The tools come from
# docs/openapi.yaml with no MCP code of their own.
class McpChangeToolsTest < McpIntegrationTest
  TEXT = "## 1. Model\n\n- [ ] 1.1 Add the table\n- [ ] 1.2 Add the model\n"
  CHANGE_TOOLS = %w[listChanges createChange showChange updateChange archiveChange listChangeTasks setTaskChange importOpenspecChange
    showChangeFile listChangeComments createChangeComment].freeze
  READ_TOOLS = %w[listChanges showChange listChangeTasks showChangeFile listChangeComments].freeze

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

  def body(result)
    assert_not result["isError"], text(result)
    JSON.parse(text(result))
  end

  def read_only_connection
    Oauth::AccessToken.create!(application: oauth_applications(:claude_ai), resource_owner_id: users(:two).id, scopes: "read",
      expires_in: 3600, use_refresh_token: true).plaintext_token
  end

  test "the change tools are listed, and no sprint, milestone or showOpenspecChange tool" do
    names = listed_tools.keys

    assert_empty CHANGE_TOOLS - names
    assert_empty names.grep(/sprint|milestone/i)
    assert_not_includes names, "showOpenspecChange"
  end

  test "reading tools are read-only, the others write, and none is destructive but archiving" do
    tools = listed_tools

    READ_TOOLS.each { |name| assert_equal true, tools.fetch(name).dig("annotations", "readOnlyHint"), name }
    (CHANGE_TOOLS - READ_TOOLS).each { |name| assert_equal false, tools.fetch(name).dig("annotations", "readOnlyHint"), name }
    assert_equal %w[ project_id name artifacts ], tools.fetch("importOpenspecChange").dig("inputSchema", "required")
    assert_match(/How an agent works through a change/, tools.fetch("importOpenspecChange")["description"])
    assert_match(/create\s+it first \(`createChange`\) or let the first import create it/, tools.fetch("importOpenspecChange")["description"])
  end

  test "a read-only connection sees only the reading tools" do
    names = listed_tools(token: read_only_connection).keys

    assert_empty READ_TOOLS - names
    assert_empty (CHANGE_TOOLS - READ_TOOLS) & names
  end

  test "create a change, import into it, show it by name, list its tasks and archive it" do
    project_id = projects(:goal).id

    created = body(call_tool("createChange", { project_id:, name: "add-labels" }))
    imported = body(call_tool("importOpenspecChange", { project_id:, name: "add-labels", artifacts: { tasks: TEXT } }))
    assert_equal created["id"], imported["id"]
    assert_equal [ "add-labels: 1. Model" ], imported["cards"].map { it["title"] }
    assert_equal users(:two), projects(:goal).project_changes.find_by!(name: "add-labels").imported_by

    again = body(call_tool("importOpenspecChange", { project_id:, name: "add-labels", artifacts: { tasks: imported["tasks_text"] } }))
    assert_equal imported["tasks_text"], again["tasks_text"]

    shown = body(call_tool("showChange", { project_id:, id: "add-labels" }))
    assert_equal imported["tasks_text"], shown["tasks_text"]
    assert_equal [ "add-labels: 1. Model" ], body(call_tool("listChangeTasks", { project_id:, change_id: created["id"] })).map { it["title"] }
    assert_equal [ "add-labels" ], body(call_tool("listChanges", { project_id: })).map { it["name"] }

    archived = body(call_tool("archiveChange", { project_id:, change_id: "add-labels" }))
    assert archived["archived_at"].present?
    assert_empty body(call_tool("listChanges", { project_id: }))
  end

  test "setTaskChange moves a task into a change, and null takes it out" do
    project = projects(:goal)
    change = project.project_changes.create!(name: "fix-login")
    task = project.tasks.create!(title: "Task", creator: users(:two))

    moved = body(call_tool("setTaskChange", { project_id: project.id, task_id: task.key, change_id: change.id }))
    assert_equal({ "id" => change.id, "name" => "fix-login" }, moved["change"])

    taken_out = body(call_tool("setTaskChange", { project_id: project.id, task_id: task.key, change_id: nil }))
    assert_nil taken_out["change"]
    assert_nil task.reload.change
  end

  test "completeSubtask takes the key from a mark, and still takes an id" do
    change = Change::Import.new(project: projects(:goal), user: users(:two), name: "add-labels", artifacts: { "tasks" => TEXT }).run!.change
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

  test "a malformed task_id or change name is refused before any request" do
    [ [ "completeSubtask", { task_id: "not a key" } ], [ "showChange", { id: "Add Labels" } ] ].each do |name, arguments|
      result = call_tool(name, { project_id: projects(:goal).id, **arguments })
      assert result["isError"], name
    end

    assert_empty api_requests - [ "GET /api/me" ]
  end

  # The conversation of a change (add-change-conversation, task 4.2)

  test "the conversation tools take what agents send: a phase or an idea, a path, a comment body" do
    tools = listed_tools

    assert_equal %w[agent idea phase], tools.fetch("updateChange").dig("inputSchema", "properties").keys.without("project_id", "id").sort
    assert_includes tools.fetch("showChangeFile").dig("inputSchema", "required"), "path"
    assert_includes tools.fetch("createChangeComment").dig("inputSchema", "required"), "body"
    assert_match(/Ask your questions about a change here/, tools.fetch("createChangeComment")["description"])
    assert_match(/Send every file of the folder/, tools.fetch("importOpenspecChange")["description"])
  end

  test "an agent moves a change, asks in its thread, imports every file and reads one back" do
    project = projects(:goal)
    change = project.project_changes.create!(name: "export-csv", idea: "CSV for weekly reports")
    fish = create_agent(project, name: "Fish")
    token = issue_agent_token(fish, issuer: users(:one), channels: %w[mcp])

    moved = body(call_tool("updateChange", { project_id: project.id, id: "export-csv", phase: "exploring" }, token:))
    assert_equal [ "exploring", "CSV for weekly reports" ], moved.values_at("phase", "idea")
    assert_equal [ [ "phase", "Fish", true, "exploring" ] ], moved["history"].map { [ it["kind"], it.dig("actor", "name"), it.dig("actor", "agent"), it["phase"] ] }

    asked = body(call_tool("createChangeComment", { project_id: project.id, change_id: "export-csv", body: "Archived tasks too?" }, token:))
    assert_equal [ "Archived tasks too?", "Fish" ], [ asked["body"], asked.dig("author", "name") ]
    assert body(call_tool("showChange", { project_id: project.id, id: "export-csv" }, token:))["waiting_for_people"]
    assert_equal [ "Archived tasks too?" ], body(call_tool("listChangeComments", { project_id: project.id, change_id: change.id }, token:)).map { it["body"] }

    imported = body(call_tool("importOpenspecChange", { project_id: project.id, name: "export-csv",
      artifacts: { tasks: TEXT, proposal: "# Why\n", specs: { "export" => "## ADDED\n" } } }, token:))
    assert_equal [ "proposed", %w[proposal.md specs/export/spec.md] ], [ imported["phase"], imported["files"].map { it["path"] } ]
    assert_not_includes imported.to_json, "## ADDED"

    file = body(call_tool("showChangeFile", { project_id: project.id, change_id: "export-csv", path: "specs/export/spec.md" }, token:))
    assert_equal({ "path" => "specs/export/spec.md", "text" => "## ADDED\n" }, file)

    assert_equal [ [ "phase", "exploring" ], [ "import", nil ], [ "phase", "proposed" ] ], change.events.map { [ it.kind, it.phase ] }
    assert change.events.all? { it.actor == fish.user }
    assert_equal fish.user, change.comments.sole.author
  end

  # Requests (add-change-requests, task 3.2)

  REQUEST_TOOLS = %w[createRequest claimRequest finishRequest cancelRequest releaseChangeAgent reportContextFull].freeze

  test "the request tools are listed, write, and tell agents what each kind asks for" do
    tools = listed_tools

    assert_empty REQUEST_TOOLS - tools.keys
    REQUEST_TOOLS.each { |name| assert_equal false, tools.fetch(name).dig("annotations", "readOnlyHint"), name }
    assert_equal %w[project_id], tools.fetch("claimRequest").dig("inputSchema", "required")
    assert_equal %w[project_id id outcome comment], tools.fetch("finishRequest").dig("inputSchema", "required")
    assert_match(/`reply`: read the comments posted since your last finished request/, tools.fetch("claimRequest")["description"])
    assert_includes tools.fetch("createChange").dig("inputSchema", "properties").keys, "agent"
  end

  test "claimRequest with an agent's token and nothing waiting: {\"request\": null} as JSON text" do
    fish = create_agent(projects(:goal), name: "Fish")
    token = issue_agent_token(fish, issuer: users(:one), channels: %w[mcp])

    result = call_tool("claimRequest", { project_id: projects(:goal).id }, token:)

    assert_not result["isError"], text(result)
    assert_equal({ "request" => nil }, JSON.parse(text(result)))
  end

  test "claimRequest with a person's token: a tool error with the code agents_only" do
    project = projects(:goal)
    request = ChangeRequest.ask!(change: project.project_changes.create!(name: "export-csv"), kind: "explore", by: users(:one))

    result = call_tool("claimRequest", { project_id: project.id })

    assert result["isError"]
    assert_match(/agents_only/, text(result))
    assert_equal "waiting", request.reload.state
  end

  test "an agent takes a request and finishes it, and the comment is the agent's" do
    project = projects(:goal)
    change = project.project_changes.create!(name: "export-csv")
    fish = create_agent(project, name: "Fish")
    token = issue_agent_token(fish, issuer: users(:one), channels: %w[mcp])
    body(call_tool("createRequest", { project_id: project.id, change_id: "export-csv", kind: "explore" }))

    taken = body(call_tool("claimRequest", { project_id: project.id }, token:))["request"]
    assert_equal [ "explore", "taken", "export-csv", "exploring" ], [ taken["kind"], taken["state"], taken.dig("change", "name"), taken.dig("change", "phase") ]

    finished = body(call_tool("finishRequest", { project_id: project.id, id: taken["id"], outcome: "done", comment: "Archived tasks too?" }, token:))
    assert_equal [ "done", "Fish" ], [ finished["state"], finished.dig("finished_by", "name") ]
    assert_equal [ [ "Archived tasks too?", fish.user ] ], change.comments.map { [ it.body, it.author ] }

    assert_equal({ "blocked" => true }, body(call_tool("reportContextFull", { project_id: project.id }, token:)))
    released = body(call_tool("releaseChangeAgent", { project_id: project.id, change_id: "export-csv" }))
    assert_nil released["agent"]
    waiting = body(call_tool("createRequest", { project_id: project.id, change_id: "export-csv", kind: "propose" }))
    assert_equal "cancelled", body(call_tool("cancelRequest", { project_id: project.id, id: waiting["id"] }))["state"]
  end

  test "Done cannot be chosen through MCP either" do
    project = projects(:goal)
    project.project_changes.create!(name: "export-csv")

    result = call_tool("updateChange", { project_id: project.id, id: "export-csv", phase: "done" })

    assert result["isError"]
    assert_equal "idea", project.project_changes.sole.phase
  end
end
