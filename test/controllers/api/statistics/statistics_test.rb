require "test_helper"

class Api::StatisticsTest < ActionDispatch::IntegrationTest
  setup do
    @goal = projects(:goal)
    @alice = users(:one)
    @bob = users(:two)
  end

  # Without a status the task goes to the project's first column.
  def task(project, title, assignee:, **attributes)
    project.tasks.create!(title: title, creator: assignee, assignee: assignee, **attributes)
  end

  test "own overview groups open assigned tasks by project and column, excluding done and archived" do
    task(@goal, "todo", assignee: @alice, important: true)
    task(@goal, "work", assignee: @alice, status: statuses(:goal_work))
    task(@goal, "done", assignee: @alice, status: statuses(:goal_done))
    task(@goal, "archived", assignee: @alice).archive!
    task(@goal, "bob's", assignee: @bob)
    parent = task(@goal, "parent", assignee: @bob)
    @goal.tasks.create!(title: "subtask", creator: @alice, assignee: @alice, parent: parent, status: statuses(:goal_todo))
    sign_in_as @alice

    get api_statistics_overview_path

    project = response.parsed_body.sole
    assert_equal "GOAL", project.dig("project", "short_name")
    assert_equal [ [ "To Do", [ "todo" ] ], [ "Work", [ "work" ] ] ],
      project["columns"].map { |c| [ c["title"], c["tasks"].map { |t| t["title"] } ] }
    assert_equal({ "key" => "GOAL-1", "title" => "todo", "important" => true }, project["columns"].first["tasks"].first.except("id"))
  end

  test "deadline window: only tasks due within the next 7 days, soonest first" do
    task(@goal, "in 2 days", assignee: @alice, deadline: 2.days.from_now)
    task(@goal, "in 1 day", assignee: @alice, deadline: 1.day.from_now)
    task(@goal, "in 10 days", assignee: @alice, deadline: 10.days.from_now)
    task(@goal, "1 day ago", assignee: @alice, deadline: 1.day.ago)
    task(@goal, "done soon", assignee: @alice, deadline: 1.day.from_now, status: statuses(:goal_done))
    sign_in_as @alice

    get api_statistics_deadlines_path

    assert_equal [ "in 1 day", "in 2 days" ], response.parsed_body.map { |t| t["title"] }
  end

  test "partially shared work: a teammate's overview covers shared projects only" do
    private_project = Project.create!(title: "C", short_name: "CCC", owner: @bob)
    task(@goal, "shared", assignee: @bob, deadline: 1.day.from_now)
    task(private_project, "not shared", assignee: @bob, deadline: 1.day.from_now)
    sign_in_as @alice

    get api_statistics_overview_path(user_id: @bob.id)
    assert_equal [ "GOAL" ], response.parsed_body.map { |p| p.dig("project", "short_name") }

    get api_statistics_deadlines_path(user_id: @bob.id)
    assert_equal [ "shared" ], response.parsed_body.map { |t| t["title"] }
  end

  test "not a teammate: 404, same as an unknown user" do
    sign_in_as @alice

    get api_statistics_overview_path(user_id: users(:stranger).id)
    stranger = [ response.status, response.body ]
    get api_statistics_deadlines_path(user_id: 0)

    assert_equal [ 404, response.body ], stranger
  end

  test "an archived project no longer counts" do
    task(@goal, "t", assignee: @alice)
    @goal.archive!
    sign_in_as @alice

    get api_statistics_overview_path

    assert_empty response.parsed_body
  end
end
