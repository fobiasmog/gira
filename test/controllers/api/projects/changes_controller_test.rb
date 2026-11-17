require "test_helper"

# Spec changes: "Changes in a project", "Create a change", "Change lists and
# statistics", "Open a change", "Archive a change" and "Change task list";
# spec openspec-changes, "Read a change".
class Api::Projects::ChangesControllerTest < ActionDispatch::IntegrationTest
  TEXT = "## 1. Model\n\n- [ ] 1.1 Add the table\n- [ ] 1.2 Add the model\n\n## 2. API\n\n- [ ] 2.1 Add the routes\n"

  setup do
    @project = projects(:goal)
    sign_in_as users(:one)
  end

  def create_change(name, project: @project) = project.project_changes.create!(name:)

  def create_task(title, change:, status: statuses(:goal_todo), **attributes)
    @project.tasks.create!(title:, change:, status:, creator: users(:one), **attributes)
  end

  def import(name, text = TEXT)
    Change::Import.new(project: @project, user: users(:two), name:, artifacts: { "tasks" => text }).run!.change
  end

  def names = response.parsed_body.map { |change| change["name"] }

  # Create a change

  test "create: 201 with an open change and no tasks" do
    post api_project_changes_path(@project), params: { name: "export-csv" }, as: :json

    assert_response :created
    assert_equal [ "export-csv", nil, { "by_status" => {}, "total" => 0 } ], response.parsed_body.values_at("name", "archived_at", "task_counts")
    assert_equal [ "export-csv" ], @project.project_changes.kept.pluck(:name)
  end

  test "an invalid name, a missing name or the name of an open change: 422 on the name, nothing created" do
    create_change("add-labels")

    assert_no_difference -> { Change.count } do
      [ { name: "Export CSV" }, {}, { name: "add-labels" } ].each do |params|
        post api_project_changes_path(@project), params:, as: :json
        assert_response :unprocessable_content
        assert response.parsed_body.dig("error", "fields", "name").present?, params.inspect
      end
    end
  end

  test "the name of an archived change: a new change with no tasks, and the archived one keeps its tasks" do
    archived = create_change("add-labels")
    create_task("Model", change: archived)
    archived.archive!

    post api_project_changes_path(@project), params: { name: "add-labels" }, as: :json

    assert_response :created
    assert_not_equal archived.id, response.parsed_body["id"]
    assert_equal 0, response.parsed_body.dig("task_counts", "total")
    assert_equal 1, archived.tasks.count
  end

  test "the same name in two projects" do
    create_change("add-agents")
    sign_in_as users(:two)

    post api_project_changes_path(projects(:side)), params: { name: "add-agents" }, as: :json

    assert_response :created
    assert_equal [ "add-agents" ], @project.project_changes.pluck(:name)
  end

  test "an archived project or a project of others: 404 and nothing created" do
    post api_project_changes_path(projects(:side)), params: { name: "export-csv" }, as: :json
    assert_response :not_found

    @project.archive!
    post api_project_changes_path(@project), params: { name: "export-csv" }, as: :json
    assert_response :not_found
    assert_equal 0, Change.count
  end

  # Change lists and statistics

  test "open changes newest first with root task counts; none of them is active" do
    labels = create_change("add-labels")
    travel 1.minute
    create_change("export-csv")
    cards = [ create_task("A", change: labels), create_task("B", change: labels), create_task("C", change: labels, status: statuses(:goal_done)) ]
    9.times { |i| @project.tasks.create!(title: "Step #{i}", creator: users(:one), parent: cards[i % 3]) }

    get api_project_changes_path(@project)

    assert_response :success
    assert_equal %w[export-csv add-labels], names
    assert_equal({ "by_status" => { statuses(:goal_todo).id.to_s => 2, statuses(:goal_done).id.to_s => 1 }, "total" => 3 },
      response.parsed_body.last["task_counts"])
    assert response.parsed_body.none? { |change| change.key?("active") }
  end

  test "archived changes, most recently archived first, with their archive time, and not among the open ones" do
    labels = create_change("add-labels")
    login = create_change("fix-login")
    travel_to(1.day.ago) { labels.archive! }
    login.archive!

    get api_project_changes_path(@project, view: "archived")
    assert_equal %w[fix-login add-labels], names
    assert response.parsed_body.all? { |change| change["archived_at"].present? }

    get api_project_changes_path(@project)
    assert_empty response.parsed_body
  end

  test "an unknown view is 404" do
    get api_project_changes_path(@project, view: "available")

    assert_response :not_found
  end

  # Open a change; read a change

  test "open by name or id: the change, its counts and cards with their subtask counts, and its import" do
    change = import("add-labels")
    table = change.tasks.find_by!(title: "1.1 Add the table")
    table.update!(status: statuses(:goal_done))

    [ "add-labels", change.id ].each do |ref|
      get api_project_change_path(@project, ref)

      assert_response :success
      body = response.parsed_body
      assert_equal [ change.id, "add-labels", nil, 2 ], [ *body.values_at("id", "name", "archived_at"), body.dig("task_counts", "total") ]
      assert_equal [ [ "add-labels: 1. Model", 2, 1 ], [ "add-labels: 2. API", 1, 0 ] ],
        body["cards"].map { |card| card.values_at("title", "subtask_count", "subtask_done_count") }
      assert_equal users(:two).id, body.dig("imported_by", "id")
      assert body["imported_at"].present?
      assert_includes body["tasks_text"], "- [x] 1.1 Add the table <!-- goalner:#{table.key} -->"
    end
  end

  test "a change never imported has no importer, import time or text" do
    change = create_change("export-csv")

    get api_project_change_path(@project, "export-csv")

    assert_response :success
    assert_equal [ change.id, nil, nil, nil, [] ], response.parsed_body.values_at("id", "imported_by", "imported_at", "tasks_text", "cards")
  end

  test "an unknown change, a change of another project and an archived change by name: 404" do
    archived = create_change("add-labels").tap(&:archive!)
    foreign = create_change("theirs", project: projects(:side))

    [ "no-such-change", foreign.id, "theirs", "add-labels" ].each do |ref|
      get api_project_change_path(@project, ref)
      assert_response :not_found
    end

    get api_project_change_path(@project, archived.id)
    assert_response :success
    assert response.parsed_body["archived_at"].present?
  end

  # Archive a change

  test "archive with unfinished cards: archived, its cards stay with it and leave every board" do
    change = create_change("add-labels")
    cards = [ create_task("Done", change:, status: statuses(:goal_done)) ] + 3.times.map { |i| create_task("Open #{i}", change:) }

    post api_project_change_archival_path(@project, "add-labels")

    assert_response :success
    assert response.parsed_body["archived_at"].present?
    assert cards.all? { |card| card.reload.change == change }
    get api_project_changes_path(@project, view: "archived")
    assert_equal [ "add-labels" ], names
    get api_project_board_path(@project)
    assert_empty response.parsed_body["tasks"]
    get api_project_board_path(@project, change_id: change.id)
    assert_response :not_found
  end

  test "archive twice: succeeds, and the archive time is still yesterday's" do
    change = create_change("add-labels")
    travel_to(1.day.ago) { change.archive! }
    yesterday = change.reload.archived_at

    post api_project_change_archival_path(@project, change.id)

    assert_response :success
    assert_equal yesterday, change.reload.archived_at
    assert_equal yesterday.as_json, response.parsed_body["archived_at"]
  end

  test "archiving a change of another project: 404, and it stays open" do
    foreign = create_change("theirs", project: projects(:side))

    post api_project_change_archival_path(@project, foreign.id)

    assert_response :not_found
    assert_not foreign.reload.archived?
  end

  # Change task list

  test "tasks of a change: root, non-archived, in column order then position, done ones included" do
    change = create_change("export-csv")
    done = create_task("Done", change:, status: statuses(:goal_done))
    todo = 2.times.map { |i| create_task("To Do #{i}", change:) }
    @project.tasks.create!(title: "Step", creator: users(:one), parent: todo.first)
    create_task("Gone", change:).archive!
    create_task("Elsewhere", change: nil)

    get api_project_change_tasks_path(@project, "export-csv")

    assert_response :success
    assert_equal [ *todo.map(&:id), done.id ], response.parsed_body.map { |card| card["id"] }
    assert_equal statuses(:goal_done).id, response.parsed_body.last["status_id"]
  end

  test "tasks of an archived change are listed by its id" do
    change = create_change("add-labels")
    task = create_task("Model", change:)
    change.archive!

    get api_project_change_tasks_path(@project, change.id)

    assert_equal [ task.id ], response.parsed_body.map { |card| card["id"] }
  end

  test "tasks of a change of another project: 404 and no tasks" do
    foreign = create_change("theirs", project: projects(:side))
    projects(:side).tasks.create!(title: "Secret", creator: users(:two), change: foreign)

    get api_project_change_tasks_path(@project, foreign.id)

    assert_response :not_found
    assert_not_includes response.body, "Secret"
  end
end
