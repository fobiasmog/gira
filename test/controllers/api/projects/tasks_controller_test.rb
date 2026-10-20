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

  test "create without a column: at the end of the first column, in no sprint even during one, in the backlog" do
    @project.sprints.create!(title: "S1", starts_on: Date.current, ends_on: 1.week.from_now, active: true)
    create_task("Waiting")

    post api_project_tasks_path(@project), params: { title: "Later" }, as: :json

    assert_response :created
    id, status_id, position, sprint_id = response.parsed_body.values_at("id", "status_id", "position", "sprint_id")
    assert_equal [ statuses(:goal_todo).id, 1, nil ], [ status_id, position, sprint_id ]
    assert_includes task_ids("backlog"), id
    assert_not_includes task_ids("board"), id
  end

  test "create in a planned sprint: in that sprint on the first column" do
    planned = @project.sprints.create!(title: "S3", starts_on: 2.weeks.from_now, ends_on: 3.weeks.from_now)

    post api_project_tasks_path(@project), params: { title: "Rate limiting", sprint_id: planned.id }, as: :json

    assert_response :created
    task = Task.find(response.parsed_body["id"])
    assert_equal [ planned, statuses(:goal_todo) ], [ task.sprint, task.status ]
    assert_not_includes task_ids("backlog"), task.id
  end

  test "creating in an archived sprint or a sprint of another project is rejected and nothing is created" do
    archived = @project.sprints.create!(title: "Old", starts_on: Date.current, ends_on: 1.week.from_now)
    archived.archive!
    foreign = projects(:side).sprints.create!(title: "Theirs", starts_on: Date.current, ends_on: Date.current)

    [ archived, foreign ].each do |sprint|
      assert_no_difference -> { Task.count } do
        post api_project_tasks_path(@project), params: { title: "T", sprint_id: sprint.id }, as: :json
      end
      assert_response :unprocessable_content
      assert response.parsed_body.dig("error", "fields", "sprint").present?
    end
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

  test "a task can be created on a column explicitly outside the active sprint" do
    @project.sprints.create!(title: "S1", starts_on: Date.current, ends_on: 1.week.from_now, active: true)

    post api_project_tasks_path(@project), params: { title: "Outside", status_id: statuses(:goal_todo).id, sprint_id: nil }, as: :json

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

  test "placement without a column is rejected and the task stays where it was" do
    create_task("First")
    task = create_task("Second")

    patch api_project_task_placement_path(@project, task), params: { status_id: nil, position: 0 }, as: :json

    assert_response :unprocessable_content
    assert_equal [ statuses(:goal_todo).id, 1 ], [ task.reload.status_id, task.position ]
  end

  test "put a backlog task on the board: it joins the active sprint at the chosen place" do
    sprint = @project.sprints.create!(title: "S1", starts_on: Date.current, ends_on: 1.week.from_now, active: true)
    create_task("Already in Work", status: statuses(:goal_work), sprint: sprint)
    task = create_task("TEST-1")

    patch api_project_task_placement_path(@project, task),
      params: { status_id: statuses(:goal_work).id, position: 0, sprint_id: sprint.id }, as: :json

    assert_response :success
    assert_equal [ sprint.id, statuses(:goal_work).id, 0 ], response.parsed_body.values_at("sprint_id", "status_id", "position")
    assert_equal task.id, task_ids("board").first
    assert_not_includes task_ids("backlog"), task.id
  end

  test "task on a column outside the active sprint: in the backlog with its column, not on the board" do
    @project.sprints.create!(title: "S1", starts_on: Date.current, ends_on: 1.week.from_now, active: true)
    task = create_task("TEST-1")

    get api_project_tasks_path(@project, view: "backlog")

    assert_equal [ [ task.id, statuses(:goal_todo).id ] ], response.parsed_body.map { |t| t.values_at("id", "status_id") }
    assert_not_includes task_ids("board"), task.id
    get api_project_board_path(@project)
    assert_empty response.parsed_body["tasks"]
  end

  test "task in a planned sprint is not in the backlog" do
    planned = @project.sprints.create!(title: "S3", starts_on: 2.weeks.from_now, ends_on: 3.weeks.from_now)
    task = create_task("Planned", sprint: planned)

    assert_not_includes task_ids("backlog"), task.id
  end

  test "no active sprint: open tasks in no sprint are in the backlog, all tasks in no sprint are on the board" do
    open = create_task("Open")
    done = create_task("Done", status: statuses(:goal_done))

    assert_equal [ open.id ], task_ids("backlog")
    assert_equal [ open.id, done.id ], task_ids("board")
  end

  test "done task outside sprints is not in the backlog" do
    create_task("GOAL-7", status: statuses(:goal_done))

    assert_empty task_ids("backlog")
  end

  test "list done tasks outside sprints: most recently completed first, with the completion time" do
    sprint = @project.sprints.create!(title: "S1", starts_on: Date.current, ends_on: 1.week.from_now, active: true)
    yesterday = travel_to(1.day.ago) { create_task("GOAL-7", status: statuses(:goal_done)) }
    today = create_task("GOAL-8", status: statuses(:goal_done))
    create_task("GOAL-9", status: statuses(:goal_done), sprint: sprint)
    create_task("Open")

    get api_project_tasks_path(@project, view: "backlog_done")

    assert_equal [ today.id, yesterday.id ], response.parsed_body.map { |t| t["id"] }
    assert_equal today.completed_at.as_json, response.parsed_body.first["completed_at"]
  end

  test "board and backlog are in column order, then position" do
    work_first = create_task("Work 1", status: statuses(:goal_work))
    todo = 2.times.map { |i| create_task("To Do #{i}") }
    Board.new(@project).move_column(statuses(:goal_work), position: 0)

    assert_equal [ work_first.id, *todo.map(&:id) ], task_ids("backlog")
    assert_equal [ work_first.id, *todo.map(&:id) ], task_ids("board")
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
