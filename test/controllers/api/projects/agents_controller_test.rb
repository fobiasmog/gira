require "test_helper"

# Spec agents, "Create an agent in a project", "Issue agent tokens" (limits)
# and "Delete an agent" (the project's list). goal: one (owner) and two.
# side: two (owner) and stranger.
class Api::Projects::AgentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:goal)
    @user = users(:two) # "Bob": a member of goal, not its owner
    sign_in_as @user
  end

  def create_agent_request(project: @project, token: {}, **overrides)
    params = { name: "Fish", token: { name: "runner", access: "read_write", channels: %w[api mcp] }.merge(token), current_password: PASSWORD }
    post api_project_agents_path(project), params: params.merge(overrides), as: :json
  end

  def field_errors
    response.parsed_body.dig("error", "fields")
  end

  def assert_nothing_created(&block)
    assert_no_difference [ -> { Agent.count }, -> { User.count }, -> { ApiToken.count }, -> { Membership.count } ], &block
  end

  test "create: the agent joins the project at once and its first token's value is returned" do
    assert_difference [ -> { Agent.count }, -> { ApiToken.of_agents.count } ], 1 do
      create_agent_request
    end

    assert_response :created
    body = response.parsed_body
    agent = Agent.find_by!(user_id: body["id"])
    assert @project.member?(agent.user)
    assert_equal [ "Fish", true, false, 1, false ], body.values_at("name", "agent", "deleted", "token_count", "removable")
    assert_match(/\A[a-z]+-[a-z]+-\d{4}@agents\.goalner\.com\z/, body["email_address"])
    assert_equal [ @user.id, "User Two" ], body["created_by"].values_at("id", "name")
    assert_nil body["deleted_at"]

    token = body["first_token"]
    assert_match(/\Aglnr_\w{40}\z/, token["token"])
    assert_equal [ "runner", "read_write", %w[api mcp], token["token"].last(4) ], token.values_at("name", "access", "channels", "last_characters")
    assert_equal @user.id, token.dig("issuer", "id")
    assert_equal Oauth.resource, token["mcp_url"]
    assert_not token.key?("expires_at")

    get api_project_members_path(@project)
    fish = response.parsed_body.find { |member| member["name"] == "Fish" }
    assert_equal [ agent.user.id, true ], fish.values_at("id", "agent")

    sign_out
    get api_me_path, headers: bearer(token["token"])
    assert_response :success
    assert_equal agent.user.id, response.parsed_body["id"]
  end

  test "wrong password: nothing is created and the attempt counts toward lockout" do
    assert_nothing_created { create_agent_request(current_password: "wrong password") }

    assert_response :unprocessable_content
    assert field_errors["current_password"].present?
    assert_equal 1, @user.reload.failed_login_attempts
  end

  test "a locked account is refused like a wrong password, even with the right one" do
    @user.update_columns(failed_login_attempts: 10, locked_until: 30.minutes.from_now)

    assert_nothing_created { create_agent_request }

    assert_response :unprocessable_content
    assert field_errors["current_password"].present?
  end

  test "archived project: 404 and nothing is created" do
    archived = Project.create!(title: "Old", short_name: "OLD", owner: @user).tap(&:archive!)

    assert_nothing_created { create_agent_request(project: archived) }

    assert_response :not_found
  end

  test "a project the user does not belong to: 404 and nothing is created" do
    sign_in_as users(:one)

    assert_nothing_created { create_agent_request(project: projects(:side)) }

    assert_response :not_found
  end

  test "an invalid name is a validation error on the name" do
    [ "", "a" * 101 ].each do |name|
      assert_nothing_created { create_agent_request(name: name) }

      assert_response :unprocessable_content
      assert field_errors["name"].present?
    end
  end

  test "a first token that cannot be issued creates no agent, and its errors are named under token" do
    {
      { channels: %w[ftp] } => "token.channels",
      { channels: [] } => "token.channels",
      { access: "admin" } => "token.access",
      { name: "" } => "token.name"
    }.each do |token, field|
      assert_nothing_created { create_agent_request(token: token) }

      assert_response :unprocessable_content
      assert field_errors[field].present?, "#{field}: #{field_errors.inspect}"
    end
  end

  test "hourly limit: creating agents and issuing tokens share ten an hour" do
    6.times { |i| create_agent_request(name: "Agent #{i}") }
    assert_response :created
    agent = Agent.find_by!(user_id: response.parsed_body["id"])
    4.times { post api_agent_tokens_path(agent.user_id), params: { name: "t", access: "read", channels: %w[api], current_password: PASSWORD }, as: :json }
    assert_response :created

    assert_nothing_created { create_agent_request(name: "Eleventh") }

    assert_response :too_many_requests
    assert_equal "rate_limited", response.parsed_body.dig("error", "code")
  end

  test "tokens cannot create agents" do
    fish = create_agent(@project)
    sign_out

    [ "glnr_two_goal_read_write", issue_agent_token(fish, issuer: @user) ].each do |token|
      assert_no_difference -> { Agent.count } do
        post api_project_agents_path(@project), params: { name: "Spawn", token: { name: "t", access: "read", channels: %w[api] }, current_password: PASSWORD },
          headers: bearer(token), as: :json
      end

      assert_response :forbidden
      assert_equal "token_not_allowed", response.parsed_body.dig("error", "code")
    end
  end

  # The project's list

  test "the list has the project's agents, active and deleted, with creator, tokens and whether they can be removed" do
    fish = create_agent(@project, name: "Fish", created_by: users(:one))
    issue_agent_token(fish, issuer: @user)
    issue_agent_token(fish, issuer: users(:one))
    owl = create_agent(@project, name: "Owl")
    projects(:side).memberships.create!(user: owl.user)
    newt = create_agent(@project, name: "Newt")
    newt.delete!
    create_agent(projects(:side), name: "Elsewhere")

    get api_project_agents_path(@project)

    assert_response :success
    agents = response.parsed_body
    assert_equal %w[Fish Newt Owl], agents.map { |agent| agent["name"] }
    assert_equal [ fish.user.id, true, false, 2, false ], agents[0].values_at("id", "agent", "deleted", "token_count", "removable")
    assert_equal "User One", agents[0].dig("created_by", "name")
    assert_equal [ true, 0 ], agents[1].values_at("deleted", "token_count")
    assert agents[1]["deleted_at"].present?
    assert_equal [ false, true ], agents[2].values_at("deleted", "removable")
  end

  # Check-ins (spec change-requests)

  test "agent states: online with its check-in and change, offline, and never checked in" do
    fish = create_agent(@project, name: "Fish").user
    owl = create_agent(@project, name: "Owl").user
    create_agent(@project, name: "Newt")
    travel_to(2.hours.ago) { ChangeRequest.take!(project: @project, agent: owl) }
    change = @project.project_changes.create!(name: "export-csv")
    ChangeRequest.ask!(change:, kind: "explore", by: @user)
    travel_to(1.minute.ago) { ChangeRequest.take!(project: @project, agent: fish) }

    get api_project_agents_path(@project)

    agents = response.parsed_body.index_by { |agent| agent["name"] }
    assert_equal [ true, { "id" => change.id, "name" => "export-csv", "project_id" => @project.id } ], agents["Fish"].values_at("online", "working_on")
    assert agents["Fish"]["checked_in_at"].present?
    assert_equal [ false, nil ], agents["Owl"].values_at("online", "working_on")
    assert_equal @project.memberships.find_by!(user: owl).checked_in_at.as_json, agents["Owl"]["checked_in_at"]
    assert_equal [ false, nil, nil ], agents["Newt"].values_at("online", "checked_in_at", "working_on")
  end

  test "an agent on a change of a project the member does not share: busy, with the change unnamed" do
    fish = create_agent(@project, name: "Fish", created_by: users(:one)).user
    projects(:side).memberships.create!(user: fish)
    theirs = projects(:side).project_changes.create!(name: "theirs")
    theirs.update!(agent: fish, agent_taken_at: Time.current)

    sign_in_as users(:one)
    get api_project_agents_path(@project)

    assert_equal({ "id" => nil, "name" => nil, "project_id" => nil }, response.parsed_body.sole["working_on"])

    sign_in_as users(:two)
    get api_project_agents_path(@project)
    assert_equal "theirs", response.parsed_body.sole.dig("working_on", "name")
  end

  test "the list is for members only, and not for tokens" do
    create_agent(@project)

    sign_in_as users(:stranger)
    get api_project_agents_path(@project)
    assert_response :not_found

    sign_out
    get api_project_agents_path(@project), headers: bearer("glnr_two_goal_read_write")
    assert_response :forbidden
  end
end
