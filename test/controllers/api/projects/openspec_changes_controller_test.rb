require "test_helper"

# Spec openspec-changes, "Import a change" and "Cards and subtasks in their
# change"; spec api-tokens, "Endpoints available to tokens";
# add-openspec-changes design.md, decision 7.
class Api::Projects::OpenspecChangesControllerTest < ActionDispatch::IntegrationTest
  TEXT = "## 1. Model\n\n- [ ] 1.1 Add the table\n- [ ] 1.2 Add the model\n\n## 2. API\n\n- [ ] 2.1 Add the routes\n"

  setup { @project = projects(:goal) }

  def import(text = TEXT, name: "add-labels", headers: {}, **body)
    post api_project_openspec_changes_path(@project), params: { name:, artifacts: { tasks: text }, **body }, headers:, as: :json
  end

  def error_code = response.parsed_body.dig("error", "code")

  # Import a change

  test "first import: 201 with the open change, its counts, marked text and cards" do
    sign_in_as users(:one)

    import

    assert_response :created
    body = response.parsed_body
    assert_equal [ "add-labels", nil, 2 ], [ *body.values_at("name", "archived_at"), body.dig("task_counts", "total") ]
    assert_equal users(:one).id, body.dig("imported_by", "id")
    assert_equal [ "add-labels: 1. Model", "add-labels: 2. API" ], body["cards"].map { |card| card["title"] }
    assert_equal [ 2, 1 ], body["cards"].map { |card| card["subtask_count"] }
    assert body["cards"].all? { |card| card["change"] == { "id" => body["id"], "name" => "add-labels" } && card["in_tasks_md"] }
    assert_equal 5, body["tasks_text"].scan(/<!-- goalner:GOAL-\d+ -->/).size
    assert_equal [ "add-labels" ], @project.project_changes.kept.pluck(:name)
  end

  test "import again with the returned text: 200 and no task created" do
    sign_in_as users(:one)
    import
    marked = response.parsed_body["tasks_text"]

    assert_no_difference -> { Task.count } do
      import(marked)
    end
    assert_response :ok
    assert_equal marked, response.parsed_body["tasks_text"]
  end

  test "a change created by hand: the first import answers 200 and leaves its task added by hand alone" do
    sign_in_as users(:one)
    post api_project_changes_path(@project), params: { name: "export-csv" }, as: :json
    change = Change.find(response.parsed_body["id"])
    by_hand = @project.tasks.create!(title: "Rate limiting", creator: users(:one), change:)

    import(name: "export-csv")

    assert_response :ok
    assert_equal change.id, response.parsed_body["id"]
    assert_equal 6, change.tasks.count
    assert_equal [ "Rate limiting", false ], by_hand.reload.values_at(:title, :in_tasks_md)
  end

  test "cards go into their own change, whichever board is open" do
    sign_in_as users(:one)
    post api_project_changes_path(@project), params: { name: "export-csv" }, as: :json
    get api_project_board_path(@project, change_id: "export-csv")

    import

    get api_project_board_path(@project, change_id: "add-labels")
    assert_equal [ "add-labels: 1. Model", "add-labels: 2. API" ], response.parsed_body["tasks"].map { |card| card["title"] }
    get api_project_board_path(@project, change_id: "export-csv")
    assert_empty response.parsed_body["tasks"]
  end

  test "a refused import is 422 with the field and line, and changes nothing" do
    sign_in_as users(:one)

    assert_no_difference [ -> { Task.count }, -> { Change.count } ] do
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

    post api_project_openspec_changes_path(@project), params: { name: "add-labels", artifacts: { tasks: TEXT, notes: "# Notes" } }, as: :json
    assert_equal [ 422, [ "Notes is not an artifact Goalner imports" ] ], [ response.status, response.parsed_body.dig("error", "fields", "notes") ]
    assert_equal 0, Change.count
  end

  test "a re-import without marks is 409 keys_missing with the marked text" do
    sign_in_as users(:one)
    import
    marked = response.parsed_body["tasks_text"]

    assert_no_difference -> { Task.count } do
      import
    end

    assert_response :conflict
    assert_equal "keys_missing", error_code
    assert_equal marked, response.parsed_body["tasks_text"]
  end

  test "importing an archived change's marked text: 422 naming the first marked line, and no change created" do
    sign_in_as users(:one)
    import
    marked = response.parsed_body["tasks_text"]
    @project.project_changes.find_by!(name: "add-labels").archive!

    assert_no_difference [ -> { Task.count }, -> { Change.count } ] do
      import(marked)
    end

    assert_response :unprocessable_content
    assert_match(/\ATasks line 1: the mark names GOAL-\d+, which does not belong to this change\z/, response.parsed_body.dig("error", "fields", "tasks").first)
  end

  test "an archived project or a project of others: 404, nothing created" do
    sign_in_as users(:one)
    @project.archive!
    import
    assert_response :not_found

    post api_project_openspec_changes_path(projects(:side)), params: { name: "x", artifacts: { tasks: TEXT } }, as: :json
    assert_response :not_found
    assert_equal 0, Change.count
  end

  # Removed paths (replace-sprints-with-changes, task 3.6)

  test "reading a change by its old path, and the sprint and milestone paths, get the JSON 404" do
    sign_in_as users(:one)
    import
    task = @project.tasks.first

    [ [ :get, "openspec_changes/add-labels" ], [ :get, "sprints" ], [ :post, "sprints" ], [ :get, "milestones" ],
      [ :post, "milestones" ], [ :put, "tasks/#{task.id}/sprint" ], [ :get, "tasks?view=backlog" ] ].each do |verb, path|
      send(verb, "/api/projects/#{@project.id}/#{path}", as: :json)
      assert_response :not_found
      assert_equal "not_found", error_code, path
    end
  end

  # Tasks name their change

  test "listing tasks of several changes loads the changes in one query" do
    sign_in_as users(:one)
    import(name: "add-labels")
    import("## 1. X\n- [ ] 1.1 Y\n", name: "add-agents")
    @project.tasks.update_all(assignee_id: users(:one).id)

    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?('FROM "changes"') }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get api_project_tasks_path(@project, view: "assigned") }

    assert_response :success
    assert_equal %w[add-agents add-labels], response.parsed_body.map { |task| task.dig("change", "name") }.uniq.sort
    assert_equal 1, queries.size
  end

  # Tokens

  test "a read-write token imports, a read-only token reads" do
    import(headers: { "Authorization" => "Bearer glnr_two_goal_read_write" })
    assert_response :created
    assert_equal users(:two), @project.project_changes.find_by!(name: "add-labels").imported_by

    get api_project_change_path(@project, "add-labels"), headers: { "Authorization" => "Bearer glnr_two_goal_read" }
    assert_response :success
    assert_includes response.parsed_body["tasks_text"], "goalner:GOAL-"
  end

  test "a read-only token cannot import" do
    assert_no_difference -> { Change.count } do
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
    change = @project.project_changes.find_by!(name: "add-labels")
    assert_equal agent.user, change.imported_by
    assert change.tasks.all? { |task| task.creator == agent.user && task.assignee_id.nil? }
  end
end
