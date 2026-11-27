require "test_helper"

# Spec agent-runners, "Runners" and "List, rotate and revoke runners";
# add-runners-and-workspaces design.md, decision 1. one ("Bob") is a member of
# goal; two ("Carol") of goal and side.
class Api::Me::RunnersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bob = users(:one)
    @goal = projects(:goal)
    sign_in_as @bob
  end

  def create_runner(**overrides)
    post api_me_runners_path, params: { name: "laptop", current_password: PASSWORD }.merge(overrides), as: :json
  end

  def rotate(runner, password: PASSWORD)
    post api_me_runner_secret_rotation_path(runner), params: { current_password: password }, as: :json
  end

  def field_errors = response.parsed_body.dig("error", "fields")

  def existing(name = "laptop", user: @bob) = Runner.issue(user:, name:).tap(&:save!)

  # Runners

  test "create: the runner and its secret, shown once, and the runner is listed" do
    assert_difference -> { @bob.runners.count }, 1 do
      create_runner
    end

    assert_response :created
    body = response.parsed_body
    assert_match(/\Aglnr_runner_[1-9A-HJ-NP-Za-km-z]{40}\z/, body["secret"])
    assert_equal [ "laptop", body["secret"].last(4), [] ], body.values_at("name", "last_characters", "agents")
    assert_equal "http://www.example.com", body["goalner_url"]

    get api_me_runners_path
    assert_equal [ "laptop" ], response.parsed_body.map { |runner| runner["name"] }
    assert response.parsed_body.none? { |runner| runner.key?("secret") }

    sign_out
    get api_runner_profile_path, headers: bearer(body["secret"])
    assert_response :success
  end

  test "wrong password: no runner is created, and the attempt counts toward lockout" do
    assert_no_difference -> { Runner.count } do
      create_runner(current_password: "wrong password")
    end

    assert_response :unprocessable_content
    assert field_errors["current_password"].present?
    assert_equal 1, @bob.reload.failed_login_attempts
  end

  test "a locked account is refused, even with the right password" do
    @bob.update_columns(failed_login_attempts: 10, locked_until: 30.minutes.from_now)

    assert_no_difference -> { Runner.count } do
      create_runner
    end
    assert_response :unprocessable_content
  end

  test "runner limit: an eleventh is a validation error, and none is created" do
    10.times { |index| existing("machine #{index}") }

    assert_no_difference -> { Runner.count } do
      create_runner
    end

    assert_response :unprocessable_content
    assert field_errors["base"].present?
  end

  test "an invalid name is a validation error" do
    [ "", "a" * 101 ].each do |name|
      create_runner(name:)
      assert_response :unprocessable_content
      assert field_errors["name"].present?
    end
  end

  test "hourly limit: creating and rotating share ten an hour" do
    6.times { |index| create_runner(name: "machine #{index}") }
    runner = @bob.runners.first
    4.times { rotate(runner) }
    assert_response :created

    assert_no_difference -> { Runner.count } do
      create_runner(name: "eleventh")
    end
    assert_response :too_many_requests
    rotate(runner)
    assert_response :too_many_requests
  end

  # List, rotate and revoke runners

  test "list: with the last four characters, the last contact and the agents it runs, never the whole secret" do
    laptop = existing
    fish = create_agent(@goal, name: "Fish")
    AgentLease.lease!(agent: fish, runner: laptop)
    laptop.touch_contact!
    existing("revoked").revoke!
    existing("carol's", user: users(:two))

    get api_me_runners_path

    assert_response :success
    listed = response.parsed_body.sole
    assert_equal [ laptop.id, "laptop", laptop.last_characters ], listed.values_at("id", "name", "last_characters")
    assert listed["last_contact_at"].present?
    assert listed["created_at"].present?
    assert_equal [ [ fish.user_id, "Fish" ] ], listed["agents"].map { |agent| agent.values_at("id", "name") }
    assert_not_includes response.body, laptop.secret
  end

  test "another person's runner: 404" do
    carols = existing("carol's", user: users(:two))

    delete api_me_runner_path(carols)
    assert_response :not_found
    rotate(carols)
    assert_response :not_found
    assert_not carols.reload.revoked?
  end

  test "revoke: the runner's secret and Fish's run token get 401, and the runner is no longer listed" do
    laptop = existing
    lease = AgentLease.lease!(agent: create_agent(@goal, name: "Fish"), runner: laptop)

    delete api_me_runner_path(laptop)

    assert_response :no_content
    get api_me_runners_path
    assert_empty response.parsed_body
    delete api_me_runner_path(laptop)
    assert_response :not_found

    sign_out
    get api_runner_profile_path, headers: bearer(laptop.secret)
    assert_response :unauthorized
    get api_projects_path, headers: bearer(lease.run_token_value)
    assert_response :unauthorized
  end

  test "rotate: a new secret, the old one and Fish's run token get 401, the new one works, and the workspace stays" do
    laptop = existing
    old_secret = laptop.secret
    fish = create_agent(@goal, name: "Fish")
    lease = AgentLease.lease!(agent: fish, runner: laptop)
    change = @goal.project_changes.create!(name: "export-csv")
    workspace = Workspace.create!(change:, runner: laptop, path: "/w/export-csv", branch: "export-csv", base_branch: "main")

    rotate(laptop)

    assert_response :created
    secret = response.parsed_body["secret"]
    assert_match(/\Aglnr_runner_/, secret)
    assert_equal [ laptop.id, "laptop", secret.last(4) ], response.parsed_body.values_at("id", "name", "last_characters")

    sign_out
    get api_runner_profile_path, headers: bearer(old_secret)
    assert_response :unauthorized
    get api_projects_path, headers: bearer(lease.run_token_value)
    assert_response :unauthorized
    get api_runner_profile_path, headers: bearer(secret)
    assert_response :success
    assert_equal laptop, workspace.reload.runner
  end

  test "rotate with a wrong password: the old secret keeps working, and the attempt counts" do
    laptop = existing

    rotate(laptop, password: "wrong password")

    assert_response :unprocessable_content
    assert field_errors["current_password"].present?
    assert_equal 1, @bob.reload.failed_login_attempts
    assert_equal laptop, Runner.find_active_by_secret(laptop.secret)
  end

  test "password change: the runners' secrets keep working, and their leases go on" do
    laptop = existing
    lease = AgentLease.lease!(agent: create_agent(@goal, name: "Fish"), runner: laptop)

    patch api_me_password_path, params: { current_password: PASSWORD, password: "a brand new password" }, as: :json
    assert_response :no_content

    sign_out
    get api_runner_profile_path, headers: bearer(laptop.secret)
    assert_response :success
    assert lease.reload.live?
  end

  test "tokens and runner secrets cannot handle runners, and change nothing" do
    laptop = existing
    fish = create_agent(@goal, name: "Fish")
    sign_out

    [ "glnr_two_goal_read_write", issue_agent_token(fish, issuer: @bob) ].each do |token|
      [ -> { get api_me_runners_path, headers: bearer(token) },
        -> { post api_me_runners_path, params: { name: "spawn", current_password: PASSWORD }, headers: bearer(token), as: :json },
        -> { post api_me_runner_secret_rotation_path(laptop), params: { current_password: PASSWORD }, headers: bearer(token), as: :json },
        -> { delete api_me_runner_path(laptop), headers: bearer(token) } ].each do |request|
        request.call
        assert_response :forbidden
        assert_equal "token_not_allowed", response.parsed_body.dig("error", "code")
      end
    end

    # A runner secret is no token here: unknown, so 401.
    post api_me_runners_path, params: { name: "spawn", current_password: PASSWORD }, headers: bearer(laptop.secret), as: :json
    assert_response :unauthorized
    delete api_me_runner_path(laptop), headers: bearer(laptop.secret)
    assert_response :unauthorized

    assert_equal [ laptop ], Runner.all.to_a
    assert_equal laptop, Runner.find_active_by_secret(laptop.secret)
  end
end
