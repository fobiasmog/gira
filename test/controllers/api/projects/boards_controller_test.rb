require "test_helper"

class Api::Projects::BoardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:goal)
    sign_in_as users(:one)
  end

  def create_task(title, **attributes)
    @project.tasks.create!(title: title, creator: users(:one), status: statuses(:goal_todo), **attributes)
  end

  def board_titles
    get api_project_board_path(@project)
    response.parsed_body["tasks"].map { |task| task["title"] }.sort
  end

  test "snapshot without sprints: root, non-archived tasks on a column outside any sprint" do
    sprint = @project.sprints.create!(title: "Planned", starts_on: Date.current, ends_on: 1.week.from_now)
    parent = create_task("On board")
    @project.tasks.create!(title: "Subtask", creator: users(:one), parent: parent, status: statuses(:goal_todo))
    @project.tasks.create!(title: "Backlog", creator: users(:one))
    create_task("Archived").archive!
    create_task("In planned sprint", sprint: sprint)

    assert_equal [ "On board" ], board_titles

    body = response.parsed_body
    assert_equal [ "To Do", "Work", "Done" ], body["columns"].map { |c| c["title"] }
    assert_equal [ "User One", "User Two" ], body["members"].map { |m| m["name"] }
    assert_nil body["active_sprint"]
    assert_equal [ 1, 0, 0 ], body["tasks"].first.values_at("subtask_count", "subtask_done_count", "comment_count")
  end

  test "snapshot with an active sprint: exactly the root, non-archived tasks of that sprint" do
    sprint = @project.sprints.create!(title: "S1", starts_on: Date.current, ends_on: 1.week.from_now, active: true)
    create_task("Outside sprint")
    create_task("In sprint", sprint: sprint)
    create_task("Archived in sprint", sprint: sprint).archive!
    @project.labels.create!(title: "bug")

    assert_equal [ "In sprint" ], board_titles
    assert_equal "S1", response.parsed_body.dig("active_sprint", "title")
    assert_equal [ "bug" ], response.parsed_body["labels"].map { |l| l["title"] }
  end

  test "non-members get 404" do
    get api_project_board_path(projects(:side))

    assert_response :not_found
  end
end
