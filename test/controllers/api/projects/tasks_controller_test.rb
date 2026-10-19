require "test_helper"

class Api::Projects::TasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:goal)
    sign_in_as users(:one)
  end

  def create_task(title = "Task", **attributes)
    @project.tasks.create!(title: title, creator: users(:one), status: statuses(:goal_todo), **attributes)
  end

  def task_ids(view)
    get api_project_tasks_path(@project, view: view)
    response.parsed_body.map { |task| task["id"] }
  end

  # Creating

  test "first task in a project: number 1, key GOAL-1, creator recorded" do
    post api_project_tasks_path(@project), params: { title: "First", status_id: statuses(:goal_todo).id }, as: :json

    assert_response :created
    assert_equal [ 1, "GOAL-1" ], response.parsed_body.values_at("number", "key")
    assert_equal users(:one).id, response.parsed_body.dig("creator", "id")
  end

  test "a task created without a column goes to the backlog" do
    post api_project_tasks_path(@project), params: { title: "Later" }, as: :json

    id, status_id = response.parsed_body.values_at("id", "status_id")
    assert_nil status_id
    assert_includes task_ids("backlog"), id
  end

  test "title must be 1 to 255 characters" do
    [ "", "a" * 256 ].each do |title|
      post api_project_tasks_path(@project), params: { title: title }, as: :json
      assert_response :unprocessable_content
    end
  end

  test "a foreign column id on creation is rejected and nothing is created" do
    assert_no_difference -> { Task.count } do
      post api_project_tasks_path(@project), params: { title: "T", status_id: statuses(:side_todo).id }, as: :json
    end
    assert_response :unprocessable_content
  end

  test "create task during a sprint: it joins the active sprint and appears on the board" do
    sprint = @project.sprints.create!(title: "S1", starts_on: Date.current, ends_on: 1.week.from_now, active: true)

    post api_project_tasks_path(@project), params: { title: "In sprint", status_id: statuses(:goal_todo).id }, as: :json

    id, sprint_id = response.parsed_body.values_at("id", "sprint_id")
    assert_equal sprint.id, sprint_id
    assert_includes task_ids("board"), id
  end

  test "a board task can be created explicitly outside the active sprint" do
    @project.sprints.create!(title: "S1", starts_on: Date.current, ends_on: 1.week.from_now, active: true)

    post api_project_tasks_path(@project), params: { title: "Outside", status_id: statuses(:goal_todo).id, outside_sprint: true }, as: :json

    id, sprint_id = response.parsed_body.values_at("id", "sprint_id")
    assert_nil sprint_id
    assert_not_includes task_ids("board"), id
  end

  # Opening

  test "open by sequence number or by id" do
    11.times { create_task }
    twelfth = create_task("Twelfth")

    get api_project_task_path(@project, "GOAL-12")
    assert_equal [ twelfth.id, "GOAL-12" ], response.parsed_body.values_at("id", "key")

    get api_project_task_path(@project, twelfth.id)
    assert_equal "GOAL-12", response.parsed_body["key"]
  end

  test "a task of another project is 404 even by id" do
    other = projects(:side).tasks.create!(title: "Secret", creator: users(:two))

    get api_project_task_path(@project, other.id)

    assert_response :not_found
  end

  test "the detail includes column, creator, assignee, milestone, label, sprint, subtasks and comment count" do
    milestone = @project.milestones.create!(title: "v1")
    label = @project.labels.create!(title: "bug")
    task = create_task(assignee: users(:two), milestone: milestone, label: label)
    task.comments.create!(author: users(:one), body: "hi")
    @project.tasks.create!(title: "Sub", creator: users(:one), parent: task, status: statuses(:goal_todo))

    get api_project_task_path(@project, task.id)

    body = response.parsed_body
    assert_equal "To Do", body.dig("status", "title")
    assert_equal [ "User One", "User Two" ], [ body.dig("creator", "name"), body.dig("assignee", "name") ]
    assert_equal [ "v1", "bug" ], [ body.dig("milestone", "title"), body.dig("label", "title") ]
    assert_equal [ "Sub" ], body["subtasks"].map { |s| s["title"] }
    assert_equal 1, body["comment_count"]
  end

  # Editing

  test "assign to a member" do
    task = create_task

    patch api_project_task_path(@project, task.id), params: { assignee_id: users(:two).id }, as: :json

    assert_response :success
    assert_equal users(:two), task.reload.assignee
  end

  test "assign to an outsider: rejected, task unchanged, no notification" do
    task = create_task(title: "Original")

    assert_no_enqueued_emails do
      patch api_project_task_path(@project, task.id), params: { title: "Changed", assignee_id: users(:stranger).id }, as: :json
    end

    assert_response :unprocessable_content
    assert response.parsed_body.dig("error", "fields", "assignee").present?
    assert_equal [ "Original", nil ], [ task.reload.title, task.assignee_id ]
  end

  test "milestone from another project is rejected and the task is unchanged" do
    task = create_task
    foreign = projects(:side).milestones.create!(title: "theirs")

    patch api_project_task_path(@project, task.id), params: { milestone_id: foreign.id, important: true }, as: :json

    assert_response :unprocessable_content
    assert_equal [ nil, false ], [ task.reload.milestone_id, task.important ]
  end

  test "Markdown round trip" do
    task = create_task
    description = "# Plan\n\n- [ ] write tests\n- [x] **ship**\n"

    patch api_project_task_path(@project, task.id), params: { description: description }, as: :json
    get api_project_task_path(@project, task.id)

    assert_equal description, response.parsed_body["description"]
  end

  test "raw HTML in a description is stored and returned as plain text" do
    task = create_task
    description = "<script>alert(1)</script> <img src=x onerror=alert(2)>"

    patch api_project_task_path(@project, task.id), params: { description: description }, as: :json
    get api_project_task_path(@project, task.id)

    assert_equal description, response.parsed_body["description"]
    assert_equal "application/json", response.media_type
  end

  test "description is limited to 100,000 characters" do
    task = create_task

    patch api_project_task_path(@project, task.id), params: { description: "a" * 100_001 }, as: :json

    assert_response :unprocessable_content
  end

  test "deadline is stored in UTC, the important flag is editable, and the deadline can be cleared" do
    task = create_task

    patch api_project_task_path(@project, task.id), params: { deadline: "2026-10-05T18:30:00+03:00", important: true }, as: :json
    assert_equal Time.utc(2026, 10, 5, 15, 30), task.reload.deadline
    assert task.important
    assert_equal "2026-10-05T15:30:00.000Z", response.parsed_body["deadline"]

    patch api_project_task_path(@project, task.id), params: { deadline: nil }, as: :json
    assert_nil task.reload.deadline
  end

  # Placement and backlog

  test "send to backlog" do
    task = create_task

    patch api_project_task_placement_path(@project, task), params: { status_id: nil, position: 0 }, as: :json

    assert_response :success
    assert_not_includes task_ids("board"), task.id
    assert_includes task_ids("backlog"), task.id
  end

  test "placing a task on a column of another project is rejected" do
    task = create_task

    patch api_project_task_placement_path(@project, task), params: { status_id: statuses(:side_todo).id, position: 0 }, as: :json

    assert_response :unprocessable_content
    assert_equal statuses(:goal_todo).id, task.reload.status_id
  end

  # Subtasks

  test "add a subtask: listed under its parent, placed on the first column, not shown as its own card" do
    parent = create_task("Parent")

    post api_project_task_subtasks_path(@project, parent), params: { title: "Write tests" }, as: :json

    assert_response :created
    subtask = Task.find(response.parsed_body["id"])
    assert_equal [ parent, statuses(:goal_todo) ], [ subtask.parent, subtask.status ]
    get api_project_task_subtasks_path(@project, parent)
    assert_equal [ "Write tests" ], response.parsed_body.map { |s| s["title"] }
    assert_not_includes task_ids("board"), subtask.id
    assert_not_includes task_ids("backlog"), subtask.id
  end

  test "nested subtask is rejected and nothing is created" do
    parent = create_task("Parent")
    subtask = @project.tasks.create!(title: "Sub", creator: users(:one), parent: parent, status: statuses(:goal_todo))

    assert_no_difference -> { Task.count } do
      post api_project_task_subtasks_path(@project, subtask), params: { title: "Deeper" }, as: :json
    end
    assert_response :unprocessable_content
  end

  test "mark a subtask complete and not complete" do
    parent = create_task("Parent")
    subtask = @project.tasks.create!(title: "Sub", creator: users(:one), parent: parent, status: statuses(:goal_todo))

    put api_project_task_completion_path(@project, subtask)
    assert_equal statuses(:goal_done), subtask.reload.status
    get api_project_task_path(@project, parent.id)
    assert_equal [ true ], response.parsed_body["subtasks"].map { |s| s["complete"] }
    assert_equal 1, response.parsed_body["subtask_done_count"]

    delete api_project_task_completion_path(@project, subtask)
    assert_equal statuses(:goal_todo), subtask.reload.status
  end

  # Archive

  test "archive a task: it leaves the board and tops the archive" do
    older = create_task("Older")
    task = create_task("Fifth")
    delete api_project_task_path(@project, older.id)

    travel 1.minute do
      delete api_project_task_path(@project, task.id)
    end

    assert_response :no_content
    assert_not_includes task_ids("board"), task.id
    assert_equal [ task.id, older.id ], task_ids("archived")
  end

  test "edit an archived task: rejected and unchanged" do
    task = create_task("Kept")
    task.archive!

    patch api_project_task_path(@project, task.id), params: { title: "Changed" }, as: :json

    assert_response :unprocessable_content
    assert_equal "Kept", task.reload.title
  end

  test "archived tasks are excluded from the board, backlog and subtask lists" do
    parent = create_task("Parent")
    board_task = create_task("On board")
    backlog_task = @project.tasks.create!(title: "Backlog", creator: users(:one))
    subtask = @project.tasks.create!(title: "Sub", creator: users(:one), parent: parent, status: statuses(:goal_todo))
    [ board_task, backlog_task, subtask ].each(&:archive!)

    assert_not_includes task_ids("board"), board_task.id
    assert_not_includes task_ids("backlog"), backlog_task.id
    get api_project_task_subtasks_path(@project, parent)
    assert_empty response.parsed_body
  end

  test "archiving closes the gap in its column" do
    tasks = 3.times.map { |i| create_task("t#{i}") }

    delete api_project_task_path(@project, tasks[0].id)

    assert_equal [ 0, 1 ], tasks[1..].map { |task| task.reload.position }
  end

  test "an archived task opens read-only with description, comments, subtasks, creator and assignee" do
    task = create_task("Done deal", description: "notes", assignee: users(:two))
    task.comments.create!(author: users(:two), body: "nice")
    @project.tasks.create!(title: "Sub", creator: users(:one), parent: task, status: statuses(:goal_todo))
    task.archive!

    get api_project_task_path(@project, task.id)

    body = response.parsed_body
    assert body["archived_at"].present?
    assert_equal [ "notes", "User One", "User Two", 1, [ "Sub" ] ],
      [ body["description"], body.dig("creator", "name"), body.dig("assignee", "name"), body["comment_count"], body["subtasks"].map { |s| s["title"] } ]
  end
end
