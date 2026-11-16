require "test_helper"

# What an agent token reaches and how long it lives (spec agents, "Agent
# token reach" and "Agent token lifetime"; add-agents design.md, decisions 5
# and 6). goal: one (owner) and two. side: two (owner) and stranger.
class AgentTokenAccessTest < ActionDispatch::IntegrationTest
  setup do
    @goal = projects(:goal)
    @side = projects(:side)
    @fish = create_agent(@goal, name: "Fish")
    @side.memberships.create!(user: @fish.user)
  end

  def project_ids(token)
    get api_projects_path, headers: bearer(token)
    assert_response :success
    response.parsed_body.map { |project| project["id"] }.sort
  end

  test "projects in common: the agent's projects that the issuer belongs to" do
    token = issue_agent_token(@fish, issuer: users(:two))

    assert_equal [ @goal.id, @side.id ].sort, project_ids(token)
    get api_project_tasks_path(@goal), headers: bearer(token)
    assert_response :success
  end

  test "issuer not in a project: 404 there, as for a non-member" do
    token = issue_agent_token(@fish, issuer: users(:stranger))

    get api_project_tasks_path(@goal), headers: bearer(token)

    assert_response :not_found
    assert_equal "not_found", response.parsed_body.dig("error", "code")
    assert_equal [ @side.id ], project_ids(token)
  end

  test "a project the issuer belongs to but the agent does not is not reached" do
    other = Project.create!(title: "Other", short_name: "OTH", owner: users(:two))
    token = issue_agent_token(@fish, issuer: users(:two))

    get api_project_tasks_path(other), headers: bearer(token)

    assert_response :not_found
    assert_not_includes project_ids(token), other.id
  end

  test "issuer leaves a project: the token stops reaching it and keeps the others" do
    token = issue_agent_token(@fish, issuer: users(:two))

    @goal.remove_member!(users(:two))

    get api_project_tasks_path(@goal), headers: bearer(token)
    assert_response :not_found
    assert_equal [ @side.id ], project_ids(token)
    assert_equal 1, @fish.tokens.count, "the token is narrowed, not ended"
  end

  test "agent joins a project: reached from the next request on" do
    test_project = Project.create!(title: "Test", short_name: "TEST", owner: users(:two))
    token = issue_agent_token(@fish, issuer: users(:two))
    assert_not_includes project_ids(token), test_project.id

    test_project.memberships.create!(user: @fish.user)

    assert_includes project_ids(token), test_project.id
  end

  test "agent leaves a project: the token stops reaching it" do
    token = issue_agent_token(@fish, issuer: users(:two))

    @side.remove_member!(@fish.user)

    assert_equal [ @goal.id ], project_ids(token)
    assert_equal 1, @fish.tokens.count
  end

  test "an archived project is not reached" do
    token = issue_agent_token(@fish, issuer: users(:two))

    @side.archive!

    assert_equal [ @goal.id ], project_ids(token)
    assert_equal 1, @fish.tokens.count
  end

  test "a token that reaches no project still authenticates and sees none" do
    token = issue_agent_token(@fish, issuer: users(:one))
    @goal.remove_member!(@fish.user)

    assert_empty project_ids(token)
    get api_me_path, headers: bearer(token)
    assert_response :success
    assert_equal @fish.user.id, response.parsed_body["id"]
  end

  # Lifetime

  test "a token issued 400 days ago still authenticates as the agent" do
    token = issue_agent_token(@fish, issuer: users(:two))

    travel 400.days do
      get api_me_path, headers: bearer(token)

      assert_response :success
      assert_equal @fish.user.id, response.parsed_body["id"]
    end
  end

  test "after 100 years the token is expired like any other: 401" do
    token = issue_agent_token(@fish, issuer: users(:two))

    travel 100.years + 1.day do
      get api_me_path, headers: bearer(token)

      assert_response :unauthorized
      assert_equal "invalid_token", response.parsed_body.dig("error", "code")
    end
  end

  test "nobody's password change affects agent tokens" do
    token = issue_agent_token(@fish, issuer: users(:two))

    users(:two).update!(password: "a brand new password") # the issuer
    @fish.created_by.update!(password: "another new password") # the creator

    assert_equal [ @goal.id, @side.id ].sort, project_ids(token)
  end

  test "last use is recorded" do
    token = issue_agent_token(@fish, issuer: users(:two))

    freeze_time do
      get api_me_path, headers: bearer(token)

      assert_equal Time.current, @fish.tokens.sole.last_used_at
    end
  end

  # Spec api-tokens, "Agent tokens follow the token rules"

  test "read-only agent token writes: 403, nothing created" do
    token = issue_agent_token(@fish, issuer: users(:two), access: :read)

    assert_no_difference -> { Task.count } do
      post api_project_tasks_path(@goal), params: { title: "Nope" }, headers: bearer(token), as: :json
    end

    assert_response :forbidden
    assert_equal "insufficient_scope", response.parsed_body.dig("error", "code")
  end

  test "project administration and token management are closed to agent tokens" do
    token = issue_agent_token(@fish, issuer: users(:two))

    requests = [
      -> { patch api_project_path(@goal), params: { title: "Renamed" }, headers: bearer(token), as: :json },
      -> { post api_project_invitations_path(@goal), params: { email: "new@example.com" }, headers: bearer(token), as: :json },
      -> { delete api_project_member_path(@goal, users(:two)), headers: bearer(token) },
      -> { post api_project_statuses_path(@goal), params: { title: "Review" }, headers: bearer(token), as: :json },
      -> { get api_me_api_tokens_path, headers: bearer(token) },
      -> { post api_me_api_tokens_path, params: { name: "x" }, headers: bearer(token), as: :json }
    ]

    requests.each do |request|
      request.call

      assert_response :forbidden
      assert_equal "token_not_allowed", response.parsed_body.dig("error", "code")
    end
    assert_equal "Goalner", @goal.reload.title
    assert @goal.member?(users(:two))
  end

  test "changes made with an agent token are the agent's, not the issuer's" do
    token = issue_agent_token(@fish, issuer: users(:two))

    post api_project_tasks_path(@goal), params: { title: "From Fish" }, headers: bearer(token), as: :json

    assert_response :created
    assert_equal @fish.user, Task.find(response.parsed_body["id"]).creator
  end
end
