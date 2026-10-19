require "test_helper"

class Api::Projects::SprintsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:goal)
    sign_in_as users(:one)
  end

  def create_sprint(title, active: false, starts_on: Date.current, ends_on: 2.weeks.from_now.to_date)
    @project.sprints.create!(title: title, starts_on: starts_on, ends_on: ends_on, active: active)
  end

  def create_task(title, sprint:, status: statuses(:goal_todo), **attributes)
    @project.tasks.create!(title: title, creator: users(:one), status: status, sprint: sprint, **attributes)
  end

  test "plain sprint: exists, not active, no tasks" do
    post api_project_sprints_path(@project), params: { title: "S1", starts_on: "2026-10-05", ends_on: "2026-10-18" }, as: :json

    assert_response :created
    assert_equal [ "S1", false, 0 ], response.parsed_body.values_at("title", "active").push(response.parsed_body.dig("task_counts", "total"))
  end

  test "invalid dates" do
    post api_project_sprints_path(@project), params: { title: "S1", starts_on: "2026-10-18", ends_on: "2026-10-05" }, as: :json

    assert_response :unprocessable_content
    assert response.parsed_body.dig("error", "fields", "ends_on").present?
  end

  test "title must be 1 to 100 characters" do
    post api_project_sprints_path(@project), params: { title: "a" * 101, starts_on: "2026-10-05", ends_on: "2026-10-18" }, as: :json

    assert_response :unprocessable_content
  end

  test "activate another sprint: only one is active and the board shows its tasks" do
    s1 = create_sprint("S1", active: true)
    s2 = create_sprint("S2")
    create_task("in S2", sprint: s2)

    post api_project_sprint_activation_path(@project, s2)

    assert_response :success
    assert s2.reload.active
    assert_not s1.reload.active
    get api_project_board_path(@project)
    assert_equal [ "in S2" ], response.parsed_body["tasks"].map { |t| t["title"] }
  end

  test "the database allows only one active sprint per project" do
    create_sprint("S1", active: true)

    assert_raises(ActiveRecord::RecordNotUnique) { create_sprint("S2", active: true) }
  end

  test "carry over at creation: open tasks are copied and linked, done tasks stay" do
    s1 = create_sprint("S1", active: true)
    open_tasks = 4.times.map { |i| create_task("open#{i}", sprint: s1, assignee: users(:two)) }
    3.times { |i| create_task("done#{i}", sprint: s1, status: statuses(:goal_done)) }
    create_task("archived", sprint: s1).archive!
    @project.tasks.create!(title: "sub", creator: users(:one), parent: open_tasks.first, status: statuses(:goal_todo))

    post api_project_sprints_path(@project),
      params: { title: "S2", starts_on: Date.current, ends_on: 2.weeks.from_now.to_date, activate: true, carry_over: true }, as: :json

    s2 = Sprint.find(response.parsed_body["id"])
    assert s2.active
    assert_not s1.reload.active
    copies = s2.tasks.order(:title)
    assert_equal %w[open0 open1 open2 open3], copies.map(&:title)
    assert_equal open_tasks.map(&:id).sort, copies.map(&:origin_task_id).sort
    assert copies.all? { |copy| copy.assignee == users(:two) && copy.number > 8 }
    assert_equal 7, s1.tasks.kept.count
  end

  test "put a task into a sprint" do
    sprint = create_sprint("S1")
    task = create_task("t", sprint: nil)

    put api_project_task_sprint_path(@project, task), params: { sprint_id: sprint.id }, as: :json

    assert_response :success
    assert_equal sprint, task.reload.sprint
  end

  test "sprint of another project is rejected and the task's sprint is unchanged" do
    sprint = create_sprint("S1")
    task = create_task("t", sprint: sprint)
    foreign = projects(:side).sprints.create!(title: "Theirs", starts_on: Date.current, ends_on: Date.current)

    put api_project_task_sprint_path(@project, task), params: { sprint_id: foreign.id }, as: :json

    assert_response :unprocessable_content
    assert_equal sprint, task.reload.sprint
  end

  test "sprint statistics: per-column and total counts exclude archived tasks" do
    s1 = create_sprint("S1")
    2.times { create_task("todo", sprint: s1) }
    create_task("done", sprint: s1, status: statuses(:goal_done))
    create_task("archived", sprint: s1).archive!

    get api_project_sprints_path(@project)

    counts = response.parsed_body.find { |s| s["title"] == "S1" }["task_counts"]
    assert_equal({ statuses(:goal_todo).id.to_s => 2, statuses(:goal_done).id.to_s => 1 }, counts["by_status"])
    assert_equal 3, counts["total"]
  end

  test "lists: newest first, available for planning, archived" do
    past = create_sprint("Past", starts_on: 1.month.ago.to_date, ends_on: 2.weeks.ago.to_date)
    active = create_sprint("Active", active: true, starts_on: 1.week.ago.to_date)
    future = create_sprint("Future", starts_on: 1.week.from_now.to_date, ends_on: 3.weeks.from_now.to_date)
    archived = create_sprint("Archived")
    archived.archive!

    get api_project_sprints_path(@project)
    assert_equal [ future.id, active.id, past.id ], response.parsed_body.map { |s| s["id"] }

    get api_project_sprints_path(@project, view: "available")
    assert_equal [ future.id, active.id ], response.parsed_body.map { |s| s["id"] }

    get api_project_sprints_path(@project, view: "archived")
    assert_equal [ archived.id ], response.parsed_body.map { |s| s["id"] }
  end

  test "archive with carry-over" do
    s1 = create_sprint("S1", active: true)
    s2 = create_sprint("S2")
    create_task("open", sprint: s1)
    create_task("done", sprint: s1, status: statuses(:goal_done))

    post api_project_sprint_archival_path(@project, s1), params: { carry_to_sprint_id: s2.id }, as: :json

    assert_response :success
    assert_equal [ "open" ], s2.tasks.pluck(:title)
    s1.reload
    assert s1.archived?
    assert_not s1.active
  end

  test "carrying over to a sprint of another project is rejected" do
    s1 = create_sprint("S1", active: true)
    foreign = projects(:side).sprints.create!(title: "Theirs", starts_on: Date.current, ends_on: Date.current)

    post api_project_sprint_archival_path(@project, s1), params: { carry_to_sprint_id: foreign.id }, as: :json

    assert_response :not_found
    assert_not s1.reload.archived?
  end

  test "archived tasks are excluded from sprint task lists" do
    sprint = create_sprint("S1", active: true)
    create_task("kept", sprint: sprint)
    create_task("archived", sprint: sprint).archive!

    get api_project_tasks_path(@project, view: "board")

    assert_equal [ "kept" ], response.parsed_body.map { |t| t["title"] }
  end
end
