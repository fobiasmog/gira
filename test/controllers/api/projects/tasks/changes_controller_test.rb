require "test_helper"

# Spec changes, "Tasks in a change" and "Tasks name their change".
class Api::Projects::Tasks::ChangesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:goal)
    sign_in_as users(:one)
    @login = create_change("fix-login")
    @export = create_change("export-csv")
  end

  def create_change(name, project: @project) = project.project_changes.create!(name:)

  def create_task(title, change: nil, status: statuses(:goal_todo), **attributes)
    @project.tasks.create!(title:, change:, status:, creator: users(:one), **attributes)
  end

  def put_change(task, change_id)
    put api_project_task_change_path(@project, task.key), params: { change_id: }, as: :json
  end

  test "move a task to another change: its subtasks follow, its column stays, and the old change no longer lists it" do
    task = create_task("TEST-9", change: @login, status: statuses(:goal_work))
    steps = 2.times.map { |i| create_task("Step #{i}", parent: task) }

    put_change(task, @export.id)

    assert_response :success
    assert_equal [ @export.id, statuses(:goal_work).id ], response.parsed_body.values_at("change_id", "status_id")
    assert_equal({ "id" => @export.id, "name" => "export-csv" }, response.parsed_body["change"])
    assert steps.all? { |step| step.reload.change == @export }
    get api_project_change_tasks_path(@project, @login)
    assert_empty response.parsed_body
  end

  test "take a task out of its change: in no change, same column, on the board of other tasks" do
    task = create_task("TEST-9", change: @login, status: statuses(:goal_work))

    put_change(task, nil)

    assert_response :success
    assert_equal [ nil, nil, statuses(:goal_work).id ], response.parsed_body.values_at("change_id", "change", "status_id")
    get api_project_board_path(@project)
    assert_equal [ task.id ], response.parsed_body["tasks"].map { |card| card["id"] }
  end

  test "put a task in no change into a change" do
    task = create_task("Loose")

    put_change(task, @login.id)

    assert_response :success
    assert_equal @login, task.reload.change
  end

  test "a change of another project or an archived change is rejected and the task's change is unchanged" do
    task = create_task("T", change: @login)
    archived = create_change("old").tap(&:archive!)

    [ create_change("theirs", project: projects(:side)).id, archived.id ].each do |change_id|
      put_change(task, change_id)
      assert_response :unprocessable_content
      assert response.parsed_body.dig("error", "fields", "change").present?
    end
    assert_equal @login, task.reload.change
  end

  test "a card of tasks.md stays in its change: 422" do
    labels = Change::Import.new(project: @project, user: users(:one), name: "add-labels", artifacts: { "tasks" => "## 1. Model\n- [ ] 1.1 Table\n" }).run!.change
    card = labels.tasks.roots.first

    [ @export.id, nil ].each do |change_id|
      put_change(card, change_id)
      assert_response :unprocessable_content
      assert response.parsed_body.dig("error", "fields", "change").present?
    end
    assert_equal labels, card.reload.change
  end

  test "a subtask cannot be moved on its own" do
    task = create_task("Card", change: @login)
    step = create_task("Step", parent: task)

    put_change(step, @export.id)

    assert_response :unprocessable_content
    assert_equal @login, step.reload.change
  end

  test "tasks name their change and whether they are in its tasks.md" do
    labels = Change::Import.new(project: @project, user: users(:one), name: "add-labels", artifacts: { "tasks" => "## 1. Model\n- [ ] 1.1 Table\n" }).run!.change
    card = labels.tasks.roots.first
    by_hand = create_task("Fix flaky test", change: labels)
    loose = create_task("Loose")

    get api_project_task_path(@project, card.key)
    assert_equal [ { "id" => labels.id, "name" => "add-labels" }, labels.id, true ], response.parsed_body.values_at("change", "change_id", "in_tasks_md")

    get api_project_task_path(@project, by_hand.key)
    assert_equal [ "add-labels", false ], [ response.parsed_body.dig("change", "name"), response.parsed_body["in_tasks_md"] ]

    get api_project_task_path(@project, loose.key)
    assert_equal [ nil, nil, false ], response.parsed_body.values_at("change", "change_id", "in_tasks_md")
    assert response.parsed_body.key?("change")

    card.update!(assignee: users(:one))
    get api_project_tasks_path(@project, view: "assigned")
    assert_equal [ "add-labels" ], response.parsed_body.map { |task| task.dig("change", "name") }
  end

  test "an unknown task: 404" do
    put api_project_task_change_path(@project, "GOAL-9999"), params: { change_id: @login.id }, as: :json

    assert_response :not_found
  end
end
