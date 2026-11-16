require "test_helper"

# Spec agents, "Who can see and handle an agent", "Delete an agent" and
# "Agents in API responses". goal: one (owner) and two. side: two (owner) and
# stranger.
class Api::AgentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @goal = projects(:goal)
    @side = projects(:side)
    @fish = create_agent(@goal, name: "Fish", created_by: users(:two))
    sign_in_as users(:one) # "Bob": a member of goal only
  end

  test "member of a shared project: the agent is listed with the projects they share, and can be renamed" do
    @side.memberships.create!(user: @fish.user)
    create_agent(@side, name: "Elsewhere")
    create_agent(@goal, name: "Gone").delete!

    get api_agents_path

    assert_response :success
    agents = response.parsed_body
    assert_equal [ "Fish" ], agents.map { |agent| agent["name"] }
    assert_equal [ { "id" => @goal.id, "title" => "Goalner", "short_name" => "GOAL" } ], agents.first["projects"]
    assert_equal [ @fish.user.id, true, false ], agents.first.values_at("id", "agent", "deleted")

    patch api_agent_path(@fish.user_id), params: { name: "Scout" }, as: :json

    assert_response :success
    assert_equal "Scout", response.parsed_body["name"]
    assert_equal "Scout", @fish.user.reload.name
  end

  test "a user in several of the agent's projects sees them all" do
    @side.memberships.create!(user: @fish.user)
    sign_in_as users(:two)

    get api_agents_path

    assert_equal [ "Goalner", "Side project" ], response.parsed_body.sole["projects"].map { |project| project["title"] }
  end

  test "an invalid new name is a validation error" do
    patch api_agent_path(@fish.user_id), params: { name: "a" * 101 }, as: :json

    assert_response :unprocessable_content
    assert response.parsed_body.dig("error", "fields", "name").present?
    assert_equal "Fish", @fish.user.reload.name
  end

  test "no shared project: every request about the agent is a 404, as for an unknown agent" do
    token_id = ApiToken.of_agents.find_by!(token_digest: ApiToken.digest(issue_agent_token(@fish, issuer: users(:two)))).id
    sign_in_as users(:stranger)

    requests = [
      -> { patch api_agent_path(@fish.user_id), params: { name: "Mine" }, as: :json },
      -> { delete api_agent_path(@fish.user_id) },
      -> { post api_agent_restoration_path(@fish.user_id) },
      -> { get api_agent_tokens_path(@fish.user_id) },
      -> { post api_agent_tokens_path(@fish.user_id), params: { name: "t", access: "read", channels: %w[api], current_password: PASSWORD }, as: :json },
      -> { delete api_agent_token_path(@fish.user_id, token_id) },
      -> { delete api_agent_path(0) }
    ]

    requests.each do |request|
      request.call

      assert_response :not_found
    end
    assert_equal "Fish", @fish.user.reload.name
    assert_not @fish.reload.deleted?
    assert_equal 1, @fish.tokens.count

    get api_agents_path
    assert_empty response.parsed_body
  end

  test "an agent in an archived project only is not visible" do
    solo = Project.create!(title: "Solo", short_name: "SOLO", owner: users(:one))
    agent = create_agent(solo, name: "Hermit")
    solo.archive!

    delete api_agent_path(agent.user_id)

    assert_response :not_found
  end

  test "a person's id is not an agent" do
    delete api_agent_path(users(:two).id)

    assert_response :not_found
  end

  test "creator without rights: removed from the project, the creator no longer sees the agent" do
    @goal.remove_member!(users(:two)) # two created Fish
    sign_in_as users(:two)

    patch api_agent_path(@fish.user_id), params: { name: "Mine" }, as: :json

    assert_response :not_found
    assert @goal.member?(@fish.user)
  end

  test "tokens cannot handle agents: neither a person's nor an agent's" do
    sign_out
    owl = create_agent(@goal, name: "Owl")
    tokens = [ "glnr_one_goal_read_write", issue_agent_token(owl, issuer: users(:one)), issue_agent_token(@fish, issuer: users(:one)) ]

    tokens.each do |token|
      requests = [
        -> { get api_agents_path, headers: bearer(token) },
        -> { patch api_agent_path(@fish.user_id), params: { name: "Mine" }, headers: bearer(token), as: :json },
        -> { delete api_agent_path(@fish.user_id), headers: bearer(token) },
        -> { post api_agent_restoration_path(@fish.user_id), headers: bearer(token) },
        -> { get api_agent_tokens_path(@fish.user_id), headers: bearer(token) },
        -> { post api_agent_tokens_path(@fish.user_id), params: { name: "t", access: "read", channels: %w[api] }, headers: bearer(token), as: :json },
        -> { post api_project_agent_memberships_path(@goal), params: { agent_id: owl.user_id }, headers: bearer(token), as: :json }
      ]

      requests.each do |request|
        request.call

        assert_response :forbidden
        assert_equal "token_not_allowed", response.parsed_body.dig("error", "code")
      end
    end
    assert_equal "Fish", @fish.user.reload.name
    assert_not @fish.reload.deleted?
  end

  # Delete

  test "delete: tokens die, open tasks are unassigned, done ones keep the agent marked as deleted" do
    token = issue_agent_token(@fish, issuer: users(:one))
    open_task = @goal.tasks.create!(title: "In work", creator: users(:one), assignee: @fish.user, status: statuses(:goal_work))
    done_task = @goal.tasks.create!(title: "Done", creator: users(:one), assignee: @fish.user, status: statuses(:goal_done))
    comment = open_task.comments.create!(author: @fish.user, body: "On it")

    delete api_agent_path(@fish.user_id)

    assert_response :no_content
    assert @fish.reload.deleted?
    assert_empty @fish.tokens
    assert_nil open_task.reload.assignee_id
    assert_equal @fish.user.id, done_task.reload.assignee_id

    get api_me_path, headers: bearer(token).merge("Cookie" => "")
    assert_response :unauthorized

    get api_project_task_path(@goal, done_task.id)
    assert_equal [ "Fish", true, true ], response.parsed_body["assignee"].values_at("name", "agent", "deleted")

    get api_project_task_comments_path(@goal, open_task.id)
    assert_equal [ comment.id, true, true ], [ response.parsed_body.sole["id"], *response.parsed_body.sole["author"].values_at("agent", "deleted") ]

    get api_project_members_path(@goal)
    assert_equal [ "User One", "User Two" ], response.parsed_body.map { |member| member["name"] }

    get api_project_agents_path(@goal)
    assert_equal [ [ "Fish", true ] ], response.parsed_body.map { |agent| agent.values_at("name", "deleted") }
  end

  test "across projects: deleting reaches projects the deleter is not in" do
    @side.memberships.create!(user: @fish.user)
    there = @side.tasks.create!(title: "There", creator: users(:two), assignee: @fish.user, status: @side.first_status)

    delete api_agent_path(@fish.user_id) # one is a member of goal only

    assert_response :no_content
    assert_nil there.reload.assignee_id
    sign_in_as users(:stranger) # a member of side only
    get api_project_agents_path(@side)
    assert_equal [ [ "Fish", true ] ], response.parsed_body.map { |agent| agent.values_at("name", "deleted") }
  end

  test "deleting an agent twice changes nothing" do
    delete api_agent_path(@fish.user_id)
    deleted_at = @fish.reload.deleted_at

    travel 1.hour do
      delete api_agent_path(@fish.user_id)
    end

    assert_response :no_content
    assert_equal deleted_at, @fish.reload.deleted_at
  end
end
