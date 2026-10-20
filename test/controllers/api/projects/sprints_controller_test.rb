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

  test "move to another sprint: the column stays and the task leaves the old sprint" do
    s3 = create_sprint("S3")
    s4 = create_sprint("S4")
    staying = create_task("staying", sprint: s3, status: statuses(:goal_work))
    task = create_task("GOAL-9", sprint: s3, status: statuses(:goal_work))

    put api_project_task_sprint_path(@project, task), params: { sprint_id: s4.id }, as: :json

    assert_response :success
    assert_equal [ s4, statuses(:goal_work) ], [ task.reload.sprint, task.status ]
    assert_equal [ staying ], s3.tasks.kept.to_a
  end

  test "take a task out of its sprint: it keeps its column and is in the backlog" do
    s3 = create_sprint("S3")
    task = create_task("GOAL-9", sprint: s3, status: statuses(:goal_work))

    put api_project_task_sprint_path(@project, task), params: { sprint_id: nil }, as: :json

    assert_response :success
    assert_equal [ nil, statuses(:goal_work) ], [ task.reload.sprint, task.status ]
    get api_project_tasks_path(@project, view: "backlog")
    assert_equal [ task.id ], response.parsed_body.map { |t| t["id"] }
  end

  test "send to backlog during a sprint: off the board, in the backlog with its column" do
    s1 = create_sprint("S1", active: true)
    task = create_task("GOAL-4", sprint: s1, status: statuses(:goal_work))

    put api_project_task_sprint_path(@project, task), params: { sprint_id: nil }, as: :json

    get api_project_board_path(@project)
    assert_empty response.parsed_body["tasks"]
    get api_project_tasks_path(@project, view: "backlog")
    assert_equal [ [ task.id, statuses(:goal_work).id ] ], response.parsed_body.map { |t| t.values_at("id", "status_id") }
    assert_empty s1.tasks.reload
  end

  test "an archived sprint is rejected and the task's sprint is unchanged" do
    sprint = create_sprint("S1")
    archived = create_sprint("Old")
    archived.archive!
    task = create_task("t", sprint: sprint)

    put api_project_task_sprint_path(@project, task), params: { sprint_id: archived.id }, as: :json

    assert_response :unprocessable_content
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

  # Sprint task list

  def sprint_task_titles(sprint)
    get api_project_sprint_tasks_path(@project, sprint)
    response.parsed_body.map { |task| task["title"] }
  end

  test "tasks of a planned sprint: root, non-archived, done included, in column order" do
    s3 = create_sprint("S3", starts_on: 2.weeks.from_now.to_date, ends_on: 3.weeks.from_now.to_date)
    create_task("Done one", sprint: s3, status: statuses(:goal_done))
    first = create_task("First", sprint: s3)
    create_task("Second", sprint: s3)
    create_task("Archived", sprint: s3).archive!
    @project.tasks.create!(title: "Sub", creator: users(:one), parent: first, status: statuses(:goal_todo))
    create_task("Elsewhere", sprint: nil)

    assert_equal [ "First", "Second", "Done one" ], sprint_task_titles(s3)
    assert_equal [ statuses(:goal_todo).id, 1, nil ], response.parsed_body.first.values_at("status_id", "subtask_count", "carried_to")
  end

  test "carried-over task: listed with the sprint holding its most recent copy" do
    s1 = create_sprint("S1", active: true)
    s2 = create_sprint("S2")
    s3 = create_sprint("S3")
    goal3 = create_task("GOAL-3", sprint: s1)
    create_task("Finished", sprint: s1, status: statuses(:goal_done))
    s1.carry_over_to(s2)
    s1.carry_over_to(s3)

    get api_project_sprint_tasks_path(@project, s1)

    carried = response.parsed_body.to_h { |task| [ task["title"], task["carried_to"] ] }
    assert_equal({ "id" => s3.id, "title" => "S3" }, carried["GOAL-3"])
    assert_nil carried["Finished"]
    assert_equal goal3.id, Task.find_by!(sprint: s3, title: "GOAL-3").origin_task_id
  end

  test "task list of a sprint of another project is 404" do
    foreign = projects(:side).sprints.create!(title: "Theirs", starts_on: Date.current, ends_on: Date.current)
    projects(:side).tasks.create!(title: "Secret", creator: users(:two), sprint: foreign)

    get api_project_sprint_tasks_path(@project, foreign)

    assert_response :not_found
    assert_not_includes response.body, "Secret"
  end

  test "the sprint task list's query count does not grow with the number of tasks" do
    s1 = create_sprint("S1")
    s2 = create_sprint("S2")
    count_queries = lambda do
      counter = ActiveRecord::Assertions::QueryAssertions::SQLCounter.new
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get api_project_sprint_tasks_path(@project, s1) }
      counter.log.size
    end
    create_task("t0", sprint: s1, assignee: users(:two))
    s1.carry_over_to(s2)
    baseline = count_queries.call

    4.times { |i| create_task("t#{i + 1}", sprint: s1, assignee: users(:two), status: statuses(:goal_work)) }
    s1.carry_over_to(s2)

    assert_queries_count(baseline) { get api_project_sprint_tasks_path(@project, s1) }
    assert_equal 5, response.parsed_body.count { |task| task["carried_to"] }
  end

  test "archived tasks are excluded from sprint task lists" do
    sprint = create_sprint("S1", active: true)
    create_task("kept", sprint: sprint)
    create_task("archived", sprint: sprint).archive!

    get api_project_tasks_path(@project, view: "board")

    assert_equal [ "kept" ], response.parsed_body.map { |t| t["title"] }
  end
end
