require "test_helper"

# What an API token reaches (spec api-tokens, "Token reach is limited to its
# project", "Token access level", "Endpoints available to tokens" and "Token
# lifetime and revocation"; spec security-baseline, "Deny by default"). two
# is a member of goal and side and has tokens for both.
class ApiTokenAccessTest < ActionDispatch::IntegrationTest
  setup do
    @goal = projects(:goal)
    @side = projects(:side)
  end

  def bearer(value)
    { "Authorization" => "Bearer #{value}" }
  end

  def error_code
    response.parsed_body.dig("error", "code")
  end

  def create_task(project, title = "Task")
    project.tasks.create!(title: title, creator: users(:two), status: project.first_status)
  end

  # Reach

  test "another project of the owner: 404, as for a non-member" do
    task = create_task(@side)

    [ api_project_tasks_path(@side), api_project_task_path(@side, task), api_project_board_path(@side), api_project_path(@side) ].each do |path|
      get path, headers: bearer("glnr_two_goal_read_write")
      assert_response :not_found, path
    end

    assert_no_difference -> { @side.tasks.count } do
      post api_project_tasks_path(@side), params: { title: "Elsewhere" }, headers: bearer("glnr_two_goal_read_write"), as: :json
    end
    assert_response :not_found
  end

  test "project list: only the token's project" do
    get api_projects_path, headers: bearer("glnr_two_goal_read")

    assert_response :success
    assert_equal [ @goal.id ], response.parsed_body.map { |project| project["id"] }
  end

  test "comment in another project: 404 and the comment is unchanged" do
    comment = create_task(@side).comments.create!(author: users(:two), body: "Original")

    patch api_comment_path(comment), params: { body: "Changed" }, headers: bearer("glnr_two_goal_read_write"), as: :json
    assert_response :not_found
    delete api_comment_path(comment), headers: bearer("glnr_two_goal_read_write")
    assert_response :not_found

    assert_equal "Original", comment.reload.body
    assert_nil comment.deleted_at
  end

  test "a comment in the token's project can be edited" do
    comment = create_task(@goal).comments.create!(author: users(:two), body: "Original")

    patch api_comment_path(comment), params: { body: "Changed" }, headers: bearer("glnr_two_goal_read_write"), as: :json

    assert_response :success
    assert_equal "Changed", comment.reload.body
  end

  test "foreign id with a token: a label and a sprint of another project of the owner are rejected" do
    task = create_task(@goal)
    label = @side.labels.create!(title: "theirs")
    sprint = @side.sprints.create!(title: "Theirs", starts_on: Date.current, ends_on: 1.week.from_now)
    milestone = @side.milestones.create!(title: "Theirs")
    headers = bearer("glnr_two_goal_read_write")

    put api_project_task_label_path(@goal, task), params: { label_id: label.id }, headers: headers, as: :json
    assert_response :unprocessable_content
    put api_project_task_sprint_path(@goal, task), params: { sprint_id: sprint.id }, headers: headers, as: :json
    assert_response :unprocessable_content
    patch api_project_task_path(@goal, task), params: { milestone_id: milestone.id }, headers: headers, as: :json
    assert_response :unprocessable_content
    assert_no_difference -> { Task.count } do
      post api_project_tasks_path(@goal), params: { title: "T", label_id: label.id }, headers: headers, as: :json
      post api_project_tasks_path(@goal), params: { title: "T", sprint_id: sprint.id }, headers: headers, as: :json
    end

    assert_equal [ nil, nil, nil ], task.reload.values_at(:label_id, :sprint_id, :milestone_id)
  end

  # Access level

  test "read-only token writes: 403 and nothing is created" do
    assert_no_difference -> { Task.count } do
      post api_project_tasks_path(@goal), params: { title: "Nope" }, headers: bearer("glnr_two_goal_read"), as: :json
    end

    assert_response :forbidden
    assert_equal "insufficient_scope", error_code
  end

  test "read-only token: every write method is refused" do
    task = create_task(@goal)

    patch api_project_task_path(@goal, task), params: { title: "Renamed" }, headers: bearer("glnr_two_goal_read"), as: :json
    assert_response :forbidden
    delete api_project_task_path(@goal, task), headers: bearer("glnr_two_goal_read")
    assert_response :forbidden
    put api_project_task_placement_path(@goal, task), params: { status_id: statuses(:goal_done).id }, headers: bearer("glnr_two_goal_read"), as: :json
    assert_response :forbidden

    assert_equal [ "Task", nil, statuses(:goal_todo).id ], task.reload.values_at(:title, :archived_at, :status_id)
  end

  test "read-only token reads: the board is returned" do
    task = create_task(@goal, "On the board")

    get api_project_board_path(@goal), headers: bearer("glnr_two_goal_read")

    assert_response :success
    assert_equal @goal.id, response.parsed_body.dig("project", "id")
    assert_includes response.parsed_body["tasks"].map { |card| card["id"] }, task.id
  end

  test "read-only token: HEAD is a read" do
    head api_project_board_path(@goal), headers: bearer("glnr_two_goal_read")

    assert_response :success
  end

  test "attribution: a comment made with a token is authored by the token's owner" do
    task = create_task(@goal)

    post api_project_task_comments_path(@goal, task), params: { body: "From the bot" }, headers: bearer("glnr_one_goal_read_write")

    assert_response :created
    assert_equal users(:one), task.comments.last.author
    assert_equal users(:one).id, response.parsed_body.dig("author", "id")
  end

  # Opened endpoints

  test "member list: a read-only token gets the project's members" do
    get api_project_members_path(@goal), headers: bearer("glnr_two_goal_read")

    assert_response :success
    assert_equal [ users(:one).id, users(:two).id ].sort, response.parsed_body.map { |member| member["id"] }.sort
  end

  test "column list: a read-only token gets the project's columns in board order" do
    get api_project_statuses_path(@goal), headers: bearer("glnr_two_goal_read")

    assert_response :success
    assert_equal [ statuses(:goal_todo), statuses(:goal_work), statuses(:goal_done) ].map(&:id), response.parsed_body.map { |column| column["id"] }
  end

  test "columns of another project of the owner: 404" do
    get api_project_statuses_path(@side), headers: bearer("glnr_two_goal_read")

    assert_response :not_found
  end

  test "changing columns: a read-write token gets 403 and the columns are unchanged" do
    headers = bearer("glnr_two_goal_read_write")

    assert_no_difference -> { @goal.statuses.count } do
      post api_project_statuses_path(@goal), params: { title: "Review" }, headers: headers, as: :json
      assert_equal [ 403, "token_not_allowed" ], [ response.status, error_code ]
      patch api_project_status_path(@goal, statuses(:goal_done)), params: { title: "Shipped", position: 0 }, headers: headers, as: :json
      assert_equal [ 403, "token_not_allowed" ], [ response.status, error_code ]
      delete api_project_status_path(@goal, statuses(:goal_work)), headers: headers
      assert_equal [ 403, "token_not_allowed" ], [ response.status, error_code ]
    end

    assert_equal [ "To Do", "Work", "Done" ], @goal.statuses.reload.map(&:title)
  end

  test "own profile: the token's owner" do
    get api_me_path, headers: bearer("glnr_two_goal_read")

    assert_response :success
    assert_equal [ users(:two).id, users(:two).email_address ], response.parsed_body.values_at("id", "email_address")
  end

  test "task-tracker endpoints work with a read-write token" do
    headers = bearer("glnr_two_goal_read_write")

    post api_project_tasks_path(@goal), params: { title: "Parent" }, headers: headers, as: :json
    assert_response :created
    task = Task.find(response.parsed_body["id"])

    post api_project_task_subtasks_path(@goal, task), params: { title: "Child" }, headers: headers, as: :json
    assert_response :created
    subtask = Task.find(response.parsed_body["id"])
    put api_project_task_completion_path(@goal, subtask), headers: headers
    assert_response :success

    post api_project_labels_path(@goal), params: { title: "ci" }, headers: headers, as: :json
    assert_response :created
    put api_project_task_label_path(@goal, task), params: { label_id: response.parsed_body["id"] }, headers: headers, as: :json
    assert_response :success

    post api_project_sprints_path(@goal), params: { title: "S1", starts_on: Date.current, ends_on: 1.week.from_now, activate: true }, headers: headers, as: :json
    assert_response :created
    put api_project_task_sprint_path(@goal, task), params: { sprint_id: response.parsed_body["id"] }, headers: headers, as: :json
    assert_response :success

    post api_project_milestones_path(@goal), params: { title: "M1" }, headers: headers, as: :json
    assert_response :created
    patch api_project_task_path(@goal, task), params: { milestone_id: response.parsed_body["id"] }, headers: headers, as: :json
    assert_response :success

    put api_project_task_placement_path(@goal, task), params: { status_id: statuses(:goal_work).id }, headers: headers, as: :json
    assert_response :success
    assert_equal statuses(:goal_work), task.reload.status
  end

  # Lifetime (spec api-tokens, "Token lifetime and revocation")

  test "leaving and rejoining: the token stays revoked" do
    @goal.remove_member!(users(:two))
    get api_project_board_path(@goal), headers: bearer("glnr_two_goal_read_write")
    assert_response :unauthorized

    @goal.memberships.create!(user: users(:two))
    get api_project_board_path(@goal), headers: bearer("glnr_two_goal_read_write")
    assert_response :unauthorized
  end

  test "removed by the owner: the token is revoked" do
    sign_in_as users(:one)
    delete api_project_member_path(@goal, users(:two))
    assert_response :no_content
    sign_out

    get api_project_board_path(@goal), headers: bearer("glnr_two_goal_read")
    assert_response :unauthorized
  end

  test "project archived: every member's tokens for it stop working" do
    sign_in_as users(:one)
    delete api_project_path(@goal)
    assert_response :no_content
    sign_out

    %w[glnr_two_goal_read_write glnr_two_goal_read glnr_one_goal_read_write].each do |value|
      get api_project_board_path(@goal), headers: bearer(value)
      assert_response :unauthorized, value
    end
    get api_project_board_path(@side), headers: bearer("glnr_two_side_read_write")
    assert_response :success
  end

  test "password reset: the user's tokens stop working" do
    put password_path(users(:two).password_reset_token), params: { password: "a brand new password", password_confirmation: "a brand new password" }

    get api_project_board_path(@goal), headers: bearer("glnr_two_goal_read_write")
    assert_response :unauthorized
  end
end
