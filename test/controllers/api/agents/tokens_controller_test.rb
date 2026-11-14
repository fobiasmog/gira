require "test_helper"

# Spec agents, "Issue agent tokens" and "List and revoke agent tokens". goal:
# one (owner) and two. side: two (owner) and stranger.
class Api::Agents::TokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    @fish = create_agent(projects(:goal), name: "Fish")
    @user = users(:two) # "Bob": shares goal with Fish
    sign_in_as @user
  end

  def issue(agent: @fish, **overrides)
    params = { name: "runner", access: "read", channels: %w[mcp], current_password: PASSWORD }
    post api_agent_tokens_path(agent.user_id), params: params.merge(overrides).compact, as: :json
  end

  def field_errors
    response.parsed_body.dig("error", "fields")
  end

  test "issue: the value is returned once, with no expiry, and the token is listed with its issuer" do
    assert_difference -> { @fish.tokens.count }, 1 do
      issue
    end

    assert_response :created
    body = response.parsed_body
    assert_match(/\Aglnr_\w{40}\z/, body["token"])
    assert_equal [ "runner", "read", %w[mcp], body["token"].last(4) ], body.values_at("name", "access", "channels", "last_characters")
    assert_equal Oauth.resource, body["mcp_url"]
    assert_not body.key?("expires_at")
    assert_nil @fish.tokens.sole.expires_at

    get api_agent_tokens_path(@fish.user_id)
    listed = response.parsed_body.sole
    assert_equal [ "runner", @user.id, "User Two" ], [ listed["name"], *listed["issuer"].values_at("id", "name") ]
    assert_not listed.key?("token")
  end

  test "the issued token acts as the agent on the channels it was issued for" do
    issue(channels: %w[api], access: "read_write")
    value = response.parsed_body["token"]
    sign_out

    post api_project_tasks_path(projects(:goal)), params: { title: "From Fish" }, headers: bearer(value), as: :json

    assert_response :created
    assert_equal @fish.user.id, response.parsed_body.dig("creator", "id")
  end

  test "wrong password: no token, and the attempt counts toward lockout" do
    assert_no_difference -> { ApiToken.count } do
      issue(current_password: "wrong password")
    end

    assert_response :unprocessable_content
    assert field_errors["current_password"].present?
    assert_equal 1, @user.reload.failed_login_attempts
  end

  test "token limit: an agent with 20 live tokens gets no more" do
    20.times { |i| issue_agent_token(@fish, issuer: users(:one), name: "t#{i}") }

    assert_no_difference -> { ApiToken.count } do
      issue
    end

    assert_response :unprocessable_content
    assert_equal [ "An agent can have at most 20 tokens. Revoke one to issue another." ], field_errors["base"]
  end

  test "hourly limit: the eleventh agent token in an hour gets 429" do
    owl = create_agent(projects(:goal), name: "Owl")
    10.times { |i| issue(agent: i.even? ? @fish : owl) }
    assert_response :created

    assert_no_difference -> { ApiToken.count } do
      issue
    end

    assert_response :too_many_requests
  end

  test "invalid fields are validation errors" do
    { { channels: %w[ftp] } => "channels", { channels: nil } => "channels", { access: "admin" } => "access", { name: "" } => "name",
      { name: "a" * 101 } => "name" }.each do |overrides, field|
      assert_no_difference -> { ApiToken.count } do
        issue(**overrides)
      end

      assert_response :unprocessable_content
      assert field_errors[field].present?, "#{field}: #{field_errors.inspect}"
    end
  end

  test "a deleted agent gets no tokens" do
    @fish.delete!

    assert_no_difference -> { ApiToken.count } do
      issue
    end

    assert_response :unprocessable_content
    assert_equal [ "This agent is deleted. Restore it to issue tokens." ], field_errors["base"]
  end

  test "tokens issued by others are listed, newest first, never with a whole value" do
    travel_to 2.days.ago do
      issue_agent_token(@fish, issuer: users(:one), name: "older", access: :read_write, channels: %w[api])
    end
    value = issue_agent_token(@fish, issuer: @user, name: "newer", access: :read, channels: %w[api mcp])
    sign_out
    get api_me_path, headers: bearer(value) # records a use
    sign_in_as users(:one)

    get api_agent_tokens_path(@fish.user_id)

    assert_response :success
    newer, older = response.parsed_body
    assert_equal %w[newer older], [ newer["name"], older["name"] ]
    assert_equal [ "User Two", "read", %w[api mcp], value.last(4) ], [ newer.dig("issuer", "name"), *newer.values_at("access", "channels", "last_characters") ]
    assert_equal [ "User One", "read_write", %w[api] ], [ older.dig("issuer", "name"), *older.values_at("access", "channels") ]
    assert newer["last_used_at"].present?
    assert_nil older["last_used_at"]
    assert_equal %w[access channels created_at id issuer last_characters last_used_at name], newer.keys.sort
    assert_not_includes response.body, value
  end

  test "revoke another user's token: it stops working at once, without a password" do
    value = issue_agent_token(@fish, issuer: users(:one))
    token = @fish.tokens.sole

    delete api_agent_token_path(@fish.user_id, token)

    assert_response :no_content
    assert_empty @fish.tokens
    sign_out
    get api_me_path, headers: bearer(value)
    assert_response :unauthorized
  end

  test "another agent's token, or a personal token, cannot be revoked through this agent" do
    owl = create_agent(projects(:goal), name: "Owl")
    issue_agent_token(owl, issuer: users(:one))

    [ owl.tokens.sole, api_tokens(:two_goal_read_write) ].each do |token|
      delete api_agent_token_path(@fish.user_id, token)

      assert_response :not_found
      assert ApiToken.exists?(token.id)
    end
  end

  test "an agent's tokens are not among anyone's personal tokens" do
    issue
    issue_agent_token(@fish, issuer: users(:one))

    get api_me_api_tokens_path

    assert_equal %w[CI Reports Side\ sync].sort, response.parsed_body.map { |token| token["name"] }.sort
  end
end
