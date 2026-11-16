require "test_helper"

# Spec agents, "Agents in projects": adding an agent to another project.
# goal: one (owner) and two. side: two (owner) and stranger.
class Api::Projects::AgentMembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @goal = projects(:goal)
    @side = projects(:side)
    @fish = create_agent(@goal, name: "Fish")
    sign_in_as users(:two) # "Bob": a member of goal and side
  end

  def add(agent, project)
    post api_project_agent_memberships_path(project), params: { agent_id: agent.user_id }, as: :json
  end

  test "add to another project: the agent joins at once and can be assigned its tasks" do
    task = @side.tasks.create!(title: "Side work", creator: users(:two), status: @side.first_status)

    assert_no_enqueued_emails { add @fish, @side }

    assert_response :created
    assert_equal [ @fish.user.id, "Fish", true ], response.parsed_body.values_at("id", "name", "agent")
    assert @side.member?(@fish.user)
    assert @goal.member?(@fish.user)

    patch api_project_task_path(@side, task.id), params: { assignee_id: @fish.user.id }, as: :json
    assert_response :success
    assert_equal @fish.user.id, task.reload.assignee_id
  end

  test "project the user does not belong to: 404 and the agent does not join" do
    sign_in_as users(:one) # a member of goal only

    add @fish, @side

    assert_response :not_found
    assert_not @side.member?(@fish.user)
  end

  test "an agent the user cannot see: 404 and the agent does not join" do
    sign_in_as users(:stranger) # a member of side only; Fish is in goal

    add @fish, @side

    assert_response :not_found
    assert_not @side.member?(@fish.user)
  end

  test "a deleted agent is not added" do
    @fish.delete!

    add @fish, @side

    assert_response :not_found
    assert_not @side.member?(@fish.user)
  end

  test "a person's id is not an agent" do
    add Struct.new(:user_id).new(users(:one).id), @side

    assert_response :not_found
    assert_not @side.member?(users(:one))
  end

  test "adding an agent that is already a member changes nothing" do
    assert_no_difference -> { Membership.count } do
      add @fish, @goal
    end

    assert_response :created
  end

  test "an archived project: 404" do
    @side.archive!

    add @fish, @side

    assert_response :not_found
  end

  test "the agent id is required" do
    post api_project_agent_memberships_path(@side), params: {}, as: :json

    assert_response :unprocessable_content
    assert response.parsed_body.dig("error", "fields", "agent_id").present?
  end
end
