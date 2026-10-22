require "test_helper"

class Api::ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "valid project" do
    post api_projects_path, params: { title: "New", short_name: "NEW" }, as: :json

    assert_response :created
    project = Project.find(response.parsed_body["id"])
    assert_equal users(:one), project.owner
    assert_equal [ users(:one) ], project.members.to_a
    assert_equal [ "To Do", "Work", "Done" ], project.statuses.map(&:title)
  end

  test "invalid short name" do
    assert_no_difference -> { Project.count } do
      post api_projects_path, params: { title: "New", short_name: "goal-1" }, as: :json
    end

    assert_response :unprocessable_content
    assert response.parsed_body.dig("error", "fields", "short_name").present?
  end

  test "member lists only their non-archived projects" do
    other = Project.create!(title: "B", short_name: "BBB", owner: users(:one))
    Project.create!(title: "Archived", short_name: "ARC", owner: users(:one)).archive!

    get api_projects_path

    assert_equal [ projects(:goal).id, other.id ].sort, response.parsed_body.map { |p| p["id"] }.sort
  end

  test "non-member access gets the same 404 as a missing project" do
    get api_project_path(projects(:side))
    non_member = [ response.status, response.body ]

    get api_project_path(id: 0)

    assert_equal [ 404, response.body ], non_member
    assert_equal non_member, [ response.status, response.body ]
  end

  test "non-member cannot change or archive the project" do
    patch api_project_path(projects(:side)), params: { title: "Mine" }, as: :json
    assert_response :not_found
    delete api_project_path(projects(:side))
    assert_response :not_found
    assert_nil projects(:side).reload.archived_at
  end

  test "member tries to rename" do
    sign_in_as users(:two)

    patch api_project_path(projects(:goal)), params: { title: "Renamed" }, as: :json

    assert_response :forbidden
    assert_equal "Goalner", projects(:goal).reload.title
  end

  test "owner renames and changes the short name" do
    patch api_project_path(projects(:goal)), params: { title: "Renamed", short_name: "REN" }, as: :json

    assert_response :success
    assert_equal [ "Renamed", "REN" ], projects(:goal).reload.slice(:title, :short_name).values
  end

  test "owner archives: the project disappears for every member" do
    assert_enqueued_with(job: CallEvictionJob, args: [ projects(:goal) ]) do
      delete api_project_path(projects(:goal))
    end
    assert_response :no_content

    [ users(:one), users(:two) ].each do |member|
      sign_in_as member
      get api_projects_path
      assert_not_includes response.parsed_body.map { |p| p["id"] }, projects(:goal).id

      get api_project_path(projects(:goal))
      assert_response :not_found
    end
    assert Project.exists?(projects(:goal).id), "archived data is kept"
  end

  test "member leaves: the project disappears and their tasks become unassigned" do
    project = projects(:goal)
    task = project.tasks.create!(number: 1, title: "T", creator: users(:one), assignee: users(:two))
    sign_in_as users(:two)

    assert_enqueued_with(job: CallEvictionJob, args: [ project, users(:two) ]) do
      delete api_project_membership_path(project)
    end

    assert_response :no_content
    assert_nil task.reload.assignee_id
    get api_projects_path
    assert_not_includes response.parsed_body.map { |p| p["id"] }, project.id
    get api_project_path(project)
    assert_response :not_found
  end

  test "owner tries to leave" do
    delete api_project_membership_path(projects(:goal))

    assert_response :forbidden
    assert projects(:goal).member?(users(:one))
  end
end
