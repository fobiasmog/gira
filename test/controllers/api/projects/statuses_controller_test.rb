require "test_helper"

class Api::Projects::StatusesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:goal)
    sign_in_as users(:two) # any member manages columns
  end

  def titles(body = response.parsed_body) = body.map { |c| c["title"] }

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

  test "delete a column with tasks moves them to the backlog" do
    tasks = 3.times.map { |i| @project.tasks.create!(title: "t#{i}", creator: users(:one), status: statuses(:goal_work)) }

    delete api_project_status_path(@project, statuses(:goal_work))

    assert_equal [ "To Do", "Done" ], titles
    assert tasks.all? { |task| task.reload.status_id.nil? }
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
