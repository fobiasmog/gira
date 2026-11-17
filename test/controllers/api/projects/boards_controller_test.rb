require "test_helper"

# Spec projects, "Board snapshot"; spec project-board, "Board of a change".
class Api::Projects::BoardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:goal)
    sign_in_as users(:one)
  end

  def create_task(title, **attributes)
    @project.tasks.create!(title: title, creator: users(:one), status: statuses(:goal_todo), **attributes)
  end

  def create_change(name, project: @project) = project.project_changes.create!(name:)

  def board_titles(**params)
    get api_project_board_path(@project, **params)
    response.parsed_body["tasks"].map { |task| task["title"] }.sort
  end

  test "board without a change: root, non-archived tasks in no change, done ones included" do
    change = create_change("add-labels")
    parent = create_task("On board")
    @project.tasks.create!(title: "Subtask", creator: users(:one), parent: parent, status: statuses(:goal_todo))
    @project.tasks.create!(title: "Created without a column", creator: users(:one))
    create_task("Finished", status: statuses(:goal_done))
    create_task("Archived").archive!
    create_task("In a change", change: change)

    assert_equal [ "Created without a column", "Finished", "On board" ], board_titles

    body = response.parsed_body
    assert_equal [ "To Do", "Work", "Done" ], body["columns"].map { |c| c["title"] }
    assert_equal [ "User One", "User Two" ], body["members"].map { |m| m["name"] }
    assert_nil body["change"]
    assert body.key?("change")
    assert_equal [ "add-labels" ], body["changes"].map { |listed| listed["name"] }
    assert_equal [ 1, 0, 0 ], body["tasks"].first.values_at("subtask_count", "subtask_done_count", "comment_count")
  end

  test "board of a change: exactly its root, non-archived tasks, by id or by name" do
    labels = create_change("add-labels")
    export = create_change("export-csv")
    create_task("A", change: labels)
    create_task("B", change: labels, status: statuses(:goal_done))
    create_task("Archived A", change: labels).archive!
    create_task("C", change: export)
    create_task("D")
    @project.labels.create!(title: "bug")

    assert_equal [ "A", "B" ], board_titles(change_id: labels.id)
    assert_equal({ "id" => labels.id, "name" => "add-labels" }, response.parsed_body["change"])
    assert_equal [ "bug" ], response.parsed_body["labels"].map { |l| l["title"] }
    assert_equal [ "A", "B" ], board_titles(change_id: "add-labels")
    assert_equal [ "C" ], board_titles(change_id: "export-csv")
  end

  test "the snapshot lists the open changes, newest first, with their task counts" do
    labels = create_change("add-labels")
    export = travel(1.minute) { create_change("export-csv") }
    create_change("old").archive!
    create_task("A", change: labels)
    create_task("B", change: labels, status: statuses(:goal_done))
    @project.tasks.create!(title: "Step", creator: users(:one), parent: labels.tasks.first)

    get api_project_board_path(@project, change_id: labels.id)

    changes = response.parsed_body["changes"]
    assert_equal [ export.id, labels.id ], changes.map { |listed| listed["id"] }
    assert_equal({ "by_status" => { statuses(:goal_todo).id.to_s => 1, statuses(:goal_done).id.to_s => 1 }, "total" => 2 }, changes.last["task_counts"])
    assert_nil changes.last["archived_at"]
  end

  test "a project without open changes: no changes listed, the tasks in no change shown" do
    create_task("D")

    assert_equal [ "D" ], board_titles
    assert_equal [], response.parsed_body["changes"]
  end

  test "an archived change, an unknown change and a change of another project have no board" do
    archived = create_change("add-labels").tap(&:archive!)
    foreign = create_change("theirs", project: projects(:side))

    [ archived.id, "add-labels", "no-such-change", foreign.id ].each do |change_id|
      get api_project_board_path(@project, change_id:)
      assert_response :not_found
    end
  end

  test "the board costs the same queries however many tasks and changes it shows" do
    count_queries = lambda do
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get api_project_board_path(@project, change_id: "add-labels") }
      assert_response :success
      queries
    end
    labels = create_change("add-labels")
    create_task("First", change: labels)
    few = count_queries.call

    5.times { |i| create_task("More #{i}", change: create_change("change-#{i}")) }
    5.times { |i| create_task("Card #{i}", change: labels, label: @project.labels.create!(title: "l#{i}")) }

    assert_equal few, count_queries.call
  end

  test "non-members get 404" do
    get api_project_board_path(projects(:side))

    assert_response :not_found
  end
end
