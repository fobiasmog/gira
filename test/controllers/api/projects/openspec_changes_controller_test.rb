require "test_helper"

# Spec openspec-changes, "Import a change", "Read a change" and "Tasks name
# their change"; spec api-tokens, "Endpoints available to tokens";
# add-openspec-changes design.md, decision 7.
class Api::Projects::OpenspecChangesControllerTest < ActionDispatch::IntegrationTest
  TEXT = "## 1. Model\n\n- [ ] 1.1 Add the table\n- [ ] 1.2 Add the model\n\n## 2. API\n\n- [ ] 2.1 Add the routes\n"

  setup { @project = projects(:goal) }

  def import(text = TEXT, name: "add-labels", headers: {}, **body)
    post api_project_openspec_changes_path(@project), params: { name:, artifacts: { tasks: text }, **body }, headers:, as: :json
  end

  def error_code = response.parsed_body.dig("error", "code")

  # Import a change

  test "first import: 201 with the change, its milestone, marked text and cards" do
    sign_in_as users(:one)

    import

    assert_response :created
    body = response.parsed_body
    assert_equal "add-labels", body["name"]
    assert_equal [ "add-labels", 2, 0 ], body["milestone"].values_at("title", "total", "done")
    assert_equal users(:one).id, body.dig("imported_by", "id")
    assert_equal [ "add-labels: 1. Model", "add-labels: 2. API" ], body["cards"].map { |card| card["title"] }
    assert_equal [ 2, 1 ], body["cards"].map { |card| card["subtask_count"] }
    assert body["cards"].all? { |card| card["openspec_change"] == { "id" => body["id"], "name" => "add-labels" } }
    assert_equal 5, body["tasks"].scan(/<!-- goalner:GOAL-\d+ -->/).size
  end

  test "import again with the returned text: 200 and no task created" do
    sign_in_as users(:one)
    import
    marked = response.parsed_body["tasks"]

    assert_no_difference -> { Task.count } do
      import(marked)
    end
    assert_response :ok
    assert_equal marked, response.parsed_body["tasks"]
  end

  test "a refused import is 422 with the field and line, and changes nothing" do
    sign_in_as users(:one)

    assert_no_difference [ -> { Task.count }, -> { OpenspecChange.count }, -> { Milestone.count } ] do
      import(TEXT + "- [ ] 2.2 Bad <!-- goalner:GOAL-9999 -->\n")
    end

    assert_response :unprocessable_content
    assert_equal "validation_failed", error_code
    assert_equal [ "Tasks line 9: the mark names no task of this project" ], response.parsed_body.dig("error", "fields", "tasks")
  end

  test "an invalid name, a missing text and other artifacts are refused" do
    sign_in_as users(:one)

    import(name: "Add Labels")
    assert_equal [ 422, [ "name" ] ], [ response.status, response.parsed_body.dig("error", "fields").keys ]

    post api_project_openspec_changes_path(@project), params: { name: "add-labels" }, as: :json
    assert_equal [ 422, [ "tasks" ] ], [ response.status, response.parsed_body.dig("error", "fields").keys ]

    post api_project_openspec_changes_path(@project), params: { name: "add-labels", artifacts: { tasks: TEXT, proposal: "# Why" } }, as: :json
    assert_equal [ 422, [ "Proposal is not an artifact Goalner imports" ] ], [ response.status, response.parsed_body.dig("error", "fields", "proposal") ]
    assert_equal 0, OpenspecChange.count
  end

  test "a re-import without marks is 409 keys_missing with the marked text" do
    sign_in_as users(:one)
    import
    marked = response.parsed_body["tasks"]

    assert_no_difference -> { Task.count } do
      import
    end

    assert_response :conflict
    assert_equal "keys_missing", error_code
    assert_equal marked, response.parsed_body["tasks"]
  end

  test "an archived project or a project of others: 404, nothing created" do
    sign_in_as users(:one)
    @project.archive!
    import
    assert_response :not_found

    post api_project_openspec_changes_path(projects(:side)), params: { name: "x", artifacts: { tasks: TEXT } }, as: :json
    assert_response :not_found
    assert_equal 0, OpenspecChange.count
  end

  # Read a change

  test "read a change: its marked text with done items checked, and its cards" do
    sign_in_as users(:one)
    import
    change = @project.openspec_changes.find_by!(name: "add-labels")
    table = change.tasks.find_by!(title: "1.1 Add the table")
    table.update!(status: statuses(:goal_done))

    get api_project_openspec_change_path(@project, "add-labels")

    assert_response :success
    assert_includes response.parsed_body["tasks"], "- [x] 1.1 Add the table <!-- goalner:#{table.key} -->"
    assert_equal 2, response.parsed_body["cards"].size
  end

  test "an unknown change: 404" do
    sign_in_as users(:one)

    get api_project_openspec_change_path(@project, "no-such-change")

    assert_response :not_found
  end

  # Tasks name their change

  test "task details, the board and the assigned view name the change, and ordinary tasks name none" do
    sign_in_as users(:one)
    import
    change = @project.openspec_changes.find_by!(name: "add-labels")
    card = change.tasks.roots.first
    card.update!(assignee: users(:one))
    ordinary = @project.tasks.create!(title: "Ordinary", creator: users(:one), status: statuses(:goal_todo))

    get api_project_task_path(@project, card.key)
    assert_equal({ "id" => change.id, "name" => "add-labels" }, response.parsed_body["openspec_change"])

    get api_project_task_path(@project, ordinary)
    assert_nil response.parsed_body["openspec_change"]
    assert response.parsed_body.key?("openspec_change")

    get api_project_tasks_path(@project)
    board = response.parsed_body.index_by { |task| task["title"] }
    assert_equal "add-labels", board[card.title].dig("openspec_change", "name")
    assert_nil board["Ordinary"]["openspec_change"]

    get api_project_tasks_path(@project, view: "assigned")
    assert_equal [ "add-labels" ], response.parsed_body.map { |task| task.dig("openspec_change", "name") }

    get api_project_board_path(@project)
    assert_equal "add-labels", response.parsed_body["tasks"].find { |task| task["id"] == card.id }.dig("openspec_change", "name")
  end

  test "listing cards loads changes in one query, however many changes there are" do
    sign_in_as users(:one)
    import(name: "add-labels")
    import("## 1. X\n- [ ] 1.1 Y\n", name: "add-agents")

    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?("openspec_changes") }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get api_project_tasks_path(@project) }

    assert_response :success
    assert_equal 1, queries.size
  end

  # Tokens

  test "a read-write token imports, a read-only token reads" do
    import(headers: { "Authorization" => "Bearer glnr_two_goal_read_write" })
    assert_response :created
    assert_equal users(:two), @project.openspec_changes.find_by!(name: "add-labels").imported_by

    get api_project_openspec_change_path(@project, "add-labels"), headers: { "Authorization" => "Bearer glnr_two_goal_read" }
    assert_response :success
  end

  test "a read-only token cannot import" do
    assert_no_difference -> { OpenspecChange.count } do
      import(headers: { "Authorization" => "Bearer glnr_two_goal_read" })
    end

    assert_equal [ 403, "insufficient_scope" ], [ response.status, error_code ]
  end

  test "an agent's token makes the agent the creator, and no email is sent" do
    agent = create_agent(@project)
    value = issue_agent_token(agent, issuer: users(:one))

    assert_no_enqueued_emails do
      import(headers: bearer(value))
    end

    assert_response :created
    change = @project.openspec_changes.find_by!(name: "add-labels")
    assert_equal agent.user, change.imported_by
    assert change.tasks.all? { |task| task.creator == agent.user && task.assignee_id.nil? }
  end
end
