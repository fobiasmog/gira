require "test_helper"

# Run tokens at the API (spec agent-runners, "Run tokens" and "Renewing and
# ending a lease"; spec agents, "Agent token lifetime", "Run token ends with
# its lease"; add-runners-and-workspaces design.md, decision 2). goal: one
# (owner) and two. side: two (owner) and stranger.
class RunTokensTest < ActionDispatch::IntegrationTest
  setup do
    @bob = users(:one)
    @goal = projects(:goal)
    @fish = create_agent(@goal, name: "Fish")
    @laptop = Runner.issue(user: @bob, name: "laptop").tap(&:save!)
  end

  def lease = AgentLease.lease!(agent: @fish, runner: @laptop)

  test "reach: Fish belongs to GOAL and SIDE, Bob to GOAL only, so the run token reaches GOAL alone" do
    projects(:side).memberships.create!(user: @fish.user)

    get api_projects_path, headers: bearer(lease.run_token_value)

    assert_response :success
    assert_equal [ @goal.id ], response.parsed_body.map { |project| project["id"] }
  end

  test "attribution: a comment posted with the run token is Fish's" do
    change = @goal.project_changes.create!(name: "export-csv")

    post api_project_change_comments_path(@goal, change), params: { body: "Explored." }, headers: bearer(lease.run_token_value), as: :json

    assert_response :created
    assert_equal @fish.user, change.comments.last.author
  end

  test "run token ends with its lease: released, it gets 401, and Fish's tokens issued by people keep working" do
    issued = issue_agent_token(@fish, issuer: users(:two))
    leased = lease

    leased.end!

    get api_projects_path, headers: bearer(leased.run_token_value)
    assert_response :unauthorized
    assert_equal "invalid_token", response.parsed_body.dig("error", "code")
    get api_projects_path, headers: bearer(issued)
    assert_response :success
  end

  test "lapse: six minutes after its last renewal, the run token gets 401 and the lease has ended" do
    leased = lease

    travel 6.minutes do
      get api_projects_path, headers: bearer(leased.run_token_value)

      assert_response :unauthorized
      assert leased.reload.ended?
      assert_not ApiToken.exists?(agent_lease_id: leased.id)
    end
  end

  test "a password change of the runner's owner leaves the run token working" do
    leased = lease

    @bob.update!(password: "a brand new password")

    get api_projects_path, headers: bearer(leased.run_token_value)
    assert_response :success
  end

  test "a runner secret is an unknown token everywhere but the runner endpoints" do
    get api_projects_path, headers: bearer(@laptop.secret)

    assert_response :unauthorized
    assert_equal "invalid_token", response.parsed_body.dig("error", "code")
  end
end
