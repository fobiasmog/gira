require "test_helper"

class Api::Projects::StatusesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:goal)
    sign_in_as users(:two) # any member manages columns
  end

  def titles(body = response.parsed_body) = body.map { |c| c["title"] }

  test "list columns in board order, the last one done" do
    Board.new(@project).add_column(title: "Review")

    get api_project_statuses_path(@project)

    assert_response :success
    assert_equal [ "To Do", "Work", "Review", "Done" ], titles
    assert_equal [ 0, 1, 2, 3 ], response.parsed_body.map { |c| c["position"] }
    assert_equal [ false, false, false, true ], response.parsed_body.map { |c| c["done"] }
    assert_equal %w[ color done id position title ], response.parsed_body.first.keys.sort
  end

  test "the column list equals the board's columns" do
    get api_project_statuses_path(@project)
    columns = response.parsed_body

    get api_project_board_path(@project)

    assert_equal response.parsed_body["columns"], columns
  end

  test "a non-member cannot list the columns" do
    sign_out
    sign_in_as users(:stranger)

    get api_project_statuses_path(@project)

    assert_response :not_found
    assert_equal "not_found", response.parsed_body.dig("error", "code")
  end

  test "add a column before Done" do
    post api_project_statuses_path(@project), params: { title: "Review" }, as: :json

    assert_response :created
    assert_equal [ "To Do", "Work", "Review", "Done" ], titles
    assert_equal [ false, false, false, true ], response.parsed_body.map { |c| c["done"] }
  end

  test "rename and reorder a column" do
    patch api_project_status_path(@project, statuses(:goal_done)), params: { title: "Shipped", position: 0 }, as: :json

    assert_equal [ "Shipped", "To Do", "Work" ], titles
    assert_equal "Work", response.parsed_body.find { |c| c["done"] }["title"]
  end

  test "delete a column with tasks moves them to the first column" do
    tasks = 3.times.map { |i| @project.tasks.create!(title: "t#{i}", creator: users(:one), status: statuses(:goal_work)) }

    delete api_project_status_path(@project, statuses(:goal_work))

    assert_equal [ "To Do", "Done" ], titles
    assert_equal [ statuses(:goal_todo) ] * 3, tasks.map { |task| task.reload.status }
  end

  test "delete the only column is rejected" do
    delete api_project_status_path(@project, statuses(:goal_work))
    delete api_project_status_path(@project, statuses(:goal_done))

    delete api_project_status_path(@project, statuses(:goal_todo))

    assert_response :unprocessable_content
    assert Status.exists?(statuses(:goal_todo).id)
  end

  test "columns of another project are not reachable" do
    delete api_project_status_path(@project, statuses(:side_todo))

    assert_response :not_found
    assert Status.exists?(statuses(:side_todo).id)
  end
end
