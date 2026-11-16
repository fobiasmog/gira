require "test_helper"

# Spec agents, "Restore an agent". goal: one (owner) and two. side: two
# (owner) and stranger.
class Api::Agents::RestorationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @goal = projects(:goal)
    @side = projects(:side)
    @fish = create_agent(@goal, name: "Fish")
    @side.memberships.create!(user: @fish.user)
  end

  def member_names(project)
    get api_project_members_path(project)
    response.parsed_body.map { |member| member["name"] }
  end

  test "restore: active again in every project it belongs to, with no tokens and no tasks" do
    old_token = issue_agent_token(@fish, issuer: users(:two))
    task = @goal.tasks.create!(title: "Was Fish's", creator: users(:one), assignee: @fish.user, status: statuses(:goal_todo))
    @fish.delete!
    sign_in_as users(:stranger) # "Carol": a member of side only

    post api_agent_restoration_path(@fish.user_id)

    assert_response :created
    assert_equal [ "Fish", true, false, nil ], response.parsed_body.values_at("name", "agent", "deleted", "deleted_at")
    assert_not @fish.reload.deleted?
    assert_empty @fish.tokens
    assert_nil task.reload.assignee_id
    assert_includes member_names(@side), "Fish"

    sign_in_as users(:one)
    assert_includes member_names(@goal), "Fish"

    sign_out
    get api_me_path, headers: bearer(old_token)
    assert_response :unauthorized
  end

  test "tokens after restore: a new one works, and the old ones stay dead" do
    old_token = issue_agent_token(@fish, issuer: users(:two))
    @fish.delete!
    sign_in_as users(:two)
    post api_agent_restoration_path(@fish.user_id)

    post api_agent_tokens_path(@fish.user_id), params: { name: "again", access: "read", channels: %w[api], current_password: PASSWORD }, as: :json

    assert_response :created
    new_token = response.parsed_body["token"]
    sign_out
    get api_me_path, headers: bearer(new_token)
    assert_response :success
    get api_me_path, headers: bearer(old_token)
    assert_response :unauthorized
  end

  test "a restored agent can be assigned again" do
    @fish.delete!
    task = @goal.tasks.create!(title: "Next", creator: users(:one), status: statuses(:goal_todo))
    sign_in_as users(:one)

    patch api_project_task_path(@goal, task.id), params: { assignee_id: @fish.user.id }, as: :json
    assert_response :unprocessable_content

    post api_agent_restoration_path(@fish.user_id)
    patch api_project_task_path(@goal, task.id), params: { assignee_id: @fish.user.id }, as: :json

    assert_response :success
    assert_equal @fish.user.id, task.reload.assignee_id
  end

  test "restoring an agent that is not deleted changes nothing" do
    token = issue_agent_token(@fish, issuer: users(:two))
    sign_in_as users(:two)

    post api_agent_restoration_path(@fish.user_id)

    assert_response :created
    assert_not @fish.reload.deleted?
    assert_equal 1, @fish.tokens.count
    sign_out
    get api_me_path, headers: bearer(token)
    assert_response :success
  end

  test "someone who shares no project with the deleted agent cannot restore it" do
    @fish.delete!
    sign_in_as users(:unconfirmed)

    post api_agent_restoration_path(@fish.user_id)

    assert_response :not_found
    assert @fish.reload.deleted?
  end
end
