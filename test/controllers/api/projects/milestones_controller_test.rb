require "test_helper"

class Api::Projects::MilestonesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:goal)
    @milestone = @project.milestones.create!(title: "v1")
    sign_in_as users(:one)
  end

  def create_task(title, status: statuses(:goal_todo), **attributes)
    @project.tasks.create!(title: title, creator: users(:one), status: status, milestone: @milestone, **attributes)
  end

  test "create a milestone" do
    post api_project_milestones_path(@project), params: { title: "v2" }, as: :json

    assert_response :created
    assert_equal [ "v2", 0, 0 ], response.parsed_body.values_at("title", "total", "done")
  end

  test "title must be 1 to 100 characters" do
    post api_project_milestones_path(@project), params: { title: "" }, as: :json
    assert_response :unprocessable_content
  end

  test "progress counts exclude archived tasks" do
    3.times { |i| create_task("open#{i}") }
    2.times { |i| create_task("done#{i}", status: statuses(:goal_done)) }
    create_task("archived").archive!

    get api_project_milestones_path(@project)

    assert_equal [ [ "v1", 5, 2 ] ], response.parsed_body.map { |m| m.values_at("title", "total", "done") }
  end

  test "open a milestone: its non-archived tasks" do
    create_task("kept")
    create_task("archived").archive!

    get api_project_milestone_path(@project, @milestone)

    assert_equal "v1", response.parsed_body["title"]
    assert_equal [ "kept" ], response.parsed_body["tasks"].map { |t| t["title"] }
  end

  test "delete then recover: the same tasks are grouped again" do
    3.times { |i| create_task("t#{i}") }

    delete api_project_milestone_path(@project, @milestone)
    assert_response :no_content
    get api_project_milestones_path(@project)
    assert_empty response.parsed_body

    post api_project_milestone_recovery_path(@project, @milestone)
    get api_project_milestones_path(@project)
    assert_equal [ [ "v1", 3 ] ], response.parsed_body.map { |m| m.values_at("title", "total") }
  end

  test "assigning a deleted milestone is rejected" do
    task = @project.tasks.create!(title: "t", creator: users(:one))
    @milestone.delete!

    patch api_project_task_path(@project, task.id), params: { milestone_id: @milestone.id }, as: :json

    assert_response :unprocessable_content
    assert_nil task.reload.milestone_id
  end

  test "milestones of another project are not reachable" do
    foreign = projects(:side).milestones.create!(title: "theirs")

    get api_project_milestone_path(@project, foreign)

    assert_response :not_found
  end
end
