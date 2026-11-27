require "test_helper"
require "support/route_table"

# Spec agent-runners, "Runner authentication", "Lease an agent", "One lease
# per agent" and "Renewing and ending a lease"; spec security-baseline,
# "Cross-site request forgery protection" and "Deny by default";
# add-runners-and-workspaces design.md, decisions 1, 2 and 4. goal: one
# (owner, "Bob") and two. side: two (owner) and stranger.
class Api::Runners::LeasesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bob = users(:one)
    @goal = projects(:goal)
    @fish = create_agent(@goal, name: "Fish")
    @laptop = Runner.issue(user: @bob, name: "laptop").tap(&:save!)
  end

  def runner_headers(runner = @laptop) = bearer(runner.secret)

  def lease_request(agent = @fish, runner: @laptop)
    post api_runner_agent_lease_path(agent.user_id), headers: runner_headers(runner), as: :json
  end

  def error = response.parsed_body["error"]

  # Runner authentication

  test "read itself: the runner's name and its owner's, and its last contact recorded" do
    get api_runner_profile_path, headers: runner_headers

    assert_response :success
    assert_equal [ "laptop", "User One" ], [ response.parsed_body["name"], response.parsed_body.dig("owner", "name") ]
    assert @laptop.reload.last_contact_at > 1.minute.ago
  end

  test "agent token on a runner endpoint: 401, and no lease is created" do
    token = issue_agent_token(@fish, issuer: @bob)

    assert_no_difference -> { AgentLease.count } do
      post api_runner_agent_lease_path(@fish.user_id), headers: bearer(token), as: :json
    end

    assert_response :unauthorized
    assert_equal "invalid_runner_secret", error["code"]
  end

  test "every runner endpoint answers a session, an API token, a revoked or a missing secret with 401 and the error envelope" do
    revoked = Runner.issue(user: @bob, name: "old").tap(&:save!).tap(&:revoke!)
    sign_in_as @bob
    credentials = [ {}, bearer("glnr_two_goal_read_write"), bearer(revoked.secret), bearer("glnr_runner_unknown"), { "Authorization" => "Basic Ym9iOnNlY3JldA==" } ]

    RouteTable.routes.select { |route| RouteTable.sample_path(route).start_with?("/api/runner") }.each do |route|
      RouteTable.verbs(route).each do |verb|
        credentials.each do |headers|
          process verb.downcase.to_sym, RouteTable.sample_path(route), headers:, as: :json

          assert_equal [ 401, "invalid_runner_secret" ], [ response.status, error&.dig("code") ], "#{verb} #{RouteTable.sample_path(route)} #{headers.keys}"
        end
      end
    end
    assert_equal 0, AgentLease.count
  end

  test "runner request without a CSRF token: the lease is created" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    sign_in_as @bob

    lease_request

    assert_response :created
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "rate limit: 300 requests a minute per runner" do
    300.times { get api_runner_profile_path, headers: runner_headers }
    assert_response :success

    get api_runner_profile_path, headers: runner_headers
    assert_response :too_many_requests
    assert_equal "rate_limited", error["code"]

    other = Runner.issue(user: @bob, name: "desktop").tap(&:save!)
    get api_runner_profile_path, headers: runner_headers(other)
    assert_response :success
  end

  test "lease limit: 60 leases an hour per runner" do
    60.times { lease_request }
    assert_response :created

    assert_no_difference -> { AgentLease.count } do
      lease_request
    end
    assert_response :too_many_requests
  end

  # Lease an agent

  test "free agent: 201 with a lease, a run token, Fish's name and settings, GOAL with its short name, and no change" do
    @fish.update!(model: "opus", instructions: "Keep commits small.")

    lease_request

    assert_response :created
    body = response.parsed_body
    lease = AgentLease.find(body.dig("lease", "id"))
    assert_equal [ @laptop, @fish.user ], [ lease.runner, lease.agent ]
    assert_match(/\Aglnr_[1-9A-HJ-NP-Za-km-z]{40}\z/, body.dig("lease", "run_token"))
    assert_equal({ "id" => @fish.user_id, "name" => "Fish", "model" => "opus", "instructions" => "Keep commits small." }, body["agent"])
    assert_equal [ { "id" => @goal.id, "short_name" => "GOAL" } ], body["projects"]
    assert_nil body["change"]
    assert_nil @goal.memberships.find_by!(user: @fish.user).checked_in_at

    get api_projects_path, headers: bearer(body.dig("lease", "run_token"))
    assert_response :success
  end

  test "agent in the middle of a step: the change with its phase, base branch, session, workspace and the taken request" do
    change = @goal.project_changes.create!(name: "export-csv")
    ChangeRequest.ask!(change:, kind: "explore", by: @bob)
    first = AgentLease.lease!(agent: @fish, runner: @laptop)
    ChangeRequest.take!(project: @goal, agent: @fish.user, runner: @laptop).finish!(by: @fish.user, outcome: "done", comment: "Questions.")
    Workspace.record!(change:, runner: @laptop, path: "/home/bob/goalner/workspaces/GOAL/export-csv", branch: "export-csv")
    change.update!(phase: "proposed")
    implement = ChangeRequest.ask!(change:, kind: "implement", by: @bob)
    ChangeRequest.take!(project: @goal, agent: @fish.user, runner: @laptop)

    lease_request

    assert_response :created
    assert first.reload.ended?
    body = response.parsed_body["change"]
    assert_equal [ change.id, "export-csv", "implementing", "main", change.reload.agent_session_id ], body.values_at("id", "name", "phase", "base_branch", "session_id")
    assert_equal({ "id" => @goal.id, "short_name" => "GOAL" }, body["project"])
    assert_equal [ "laptop", "/home/bob/goalner/workspaces/GOAL/export-csv", "export-csv", "active" ], [ body.dig("workspace", "runner", "name"), *body["workspace"].values_at("path", "branch", "state") ]
    assert_equal [ implement.id, "implement", "taken" ], body["request"].values_at("id", "kind", "state")
  end

  test "agent its owner cannot see, unknown or deleted: 404, and no lease is created" do
    owl = create_agent(projects(:side), name: "Owl", created_by: users(:two))
    gone = create_agent(@goal, name: "Gone").tap(&:delete!)

    [ owl.user_id, gone.user_id, users(:two).id, 0 ].each do |id|
      post api_runner_agent_lease_path(id), headers: runner_headers, as: :json

      assert_response :not_found
      assert_equal "not_found", error["code"]
    end
    assert_equal 0, AgentLease.count
  end

  test "an agent on a change of a project the owner does not share: leased, with no change named" do
    projects(:side).memberships.create!(user: @fish.user)
    theirs = projects(:side).project_changes.create!(name: "theirs")
    theirs.update!(agent: @fish.user, agent_taken_at: Time.current)

    lease_request

    assert_response :created
    assert_nil response.parsed_body["change"]
    assert_equal [ "GOAL" ], response.parsed_body["projects"].map { |project| project["short_name"] }
  end

  # One lease per agent

  test "leased to another runner: 409 agent_leased, naming that runner and since when, and Fish keeps its lease" do
    first = AgentLease.lease!(agent: @fish, runner: @laptop)
    desktop = Runner.issue(user: @bob, name: "desktop").tap(&:save!)

    lease_request(runner: desktop)

    assert_response :conflict
    assert_equal [ "agent_leased", "laptop", first.created_at.as_json ], error.values_at("code", "runner", "leased_at")
    assert error["message"].present?
    assert first.reload.live?
  end

  test "same runner again: the first run token gets 401, and the new one works" do
    lease_request
    first = response.parsed_body.dig("lease", "run_token")
    lease_request
    second = response.parsed_body.dig("lease", "run_token")

    get api_projects_path, headers: bearer(first)
    assert_response :unauthorized
    get api_projects_path, headers: bearer(second)
    assert_response :success
  end

  test "workspace on another runner: 409 workspace_elsewhere, naming it, and no lease is created" do
    change = @goal.project_changes.create!(name: "export-csv")
    change.update!(agent: @fish.user, agent_taken_at: Time.current)
    Workspace.create!(change:, runner: @laptop, path: "/w/export-csv", branch: "export-csv", base_branch: "main")
    desktop = Runner.issue(user: @bob, name: "desktop").tap(&:save!)

    lease_request(runner: desktop)

    assert_response :conflict
    assert_equal [ "workspace_elsewhere", "laptop" ], error.values_at("code", "runner")
    assert_equal 0, AgentLease.count
  end

  # Renewing and ending a lease

  test "release: the run token gets 401, releasing again succeeds, and any of Bob's runners can lease Fish" do
    lease_request
    lease_id = response.parsed_body.dig("lease", "id")
    run_token = response.parsed_body.dig("lease", "run_token")

    delete api_runner_lease_path(lease_id), headers: runner_headers
    assert_response :no_content
    delete api_runner_lease_path(lease_id), headers: runner_headers
    assert_response :no_content

    get api_projects_path, headers: bearer(run_token)
    assert_response :unauthorized
    lease_request(runner: Runner.issue(user: @bob, name: "desktop").tap(&:save!))
    assert_response :created
  end

  test "another runner's lease: 404, and it lives on" do
    lease = AgentLease.lease!(agent: @fish, runner: @laptop)
    desktop = Runner.issue(user: @bob, name: "desktop").tap(&:save!)

    delete api_runner_lease_path(lease), headers: runner_headers(desktop)

    assert_response :not_found
    assert lease.reload.live?
  end

  # Privacy-preserving logs (task 3.8)

  test "lease request logged: neither the runner secret nor the run token is" do
    output = StringIO.new
    loggers = { Rails => Rails.logger, ActionController::Base => ActionController::Base.logger, ActiveRecord::Base => ActiveRecord::Base.logger }
    loggers.each_key { |owner| owner.logger = ActiveSupport::Logger.new(output) }

    lease_request

    log = output.string
    assert_includes log, "Api::Runners::LeasesController#create"
    assert_not_includes log, @laptop.secret
    assert_not_includes log, response.parsed_body.dig("lease", "run_token")
  ensure
    loggers.each { |owner, logger| owner.logger = logger }
  end
end
