require "test_helper"

# Spec agent-runners, "Lease an agent", "One lease per agent", "Run tokens"
# and "Renewing and ending a lease"; spec agents, "Issue agent tokens" and
# "List and revoke agent tokens"; add-runners-and-workspaces design.md,
# decision 2.
class AgentLeaseTest < ActiveSupport::TestCase
  setup do
    @bob = users(:one)
    @project = projects(:goal)
    @fish = create_agent(@project, name: "Fish")
    @laptop = Runner.issue(user: @bob, name: "laptop").tap(&:save!)
    @desktop = Runner.issue(user: @bob, name: "desktop").tap(&:save!)
  end

  def lease(runner = @laptop, agent: @fish) = AgentLease.lease!(agent:, runner:)

  def run_token(lease) = ApiToken.find_active_by_value(lease.run_token_value)

  def savepoint(&) = ActiveRecord::Base.transaction(requires_new: true, &)

  # Fish on change, as after taking its first request.
  def put_on(change, agent: @fish)
    change.update!(agent: agent.user, agent_taken_at: Time.current)
    change
  end

  def workspace(change, runner: @laptop)
    Workspace.create!(change:, runner:, path: "/home/bob/goalner/workspaces/GOAL/#{change.name}", branch: change.name, base_branch: "main")
  end

  test "the database refuses a second lease of one agent that has not ended" do
    first = lease
    assert_raises(ActiveRecord::RecordNotUnique) do
      savepoint { AgentLease.create!(agent: @fish.user, runner: @desktop, renewed_at: Time.current) }
    end

    first.end!
    assert AgentLease.create!(agent: @fish.user, runner: @desktop, renewed_at: Time.current)
  end

  # Lease an agent

  test "free agent: a live lease with a run token, and nothing else changes" do
    leased = lease

    assert leased.live?
    assert_equal @laptop, leased.runner
    assert_equal @fish.user, leased.agent
    assert_match(/\Aglnr_[1-9A-HJ-NP-Za-km-z]{40}\z/, leased.run_token_value)
    assert_nil @project.memberships.find_by(user: @fish.user).checked_in_at
    assert_equal 0, Change.where(agent_id: @fish.user_id).count
  end

  test "the run token is the agent's, issued by the runner's owner, read-write on both channels, and only while its lease lives" do
    token = run_token(lease)

    assert_equal @fish.user, token.user
    assert_equal @bob, token.issuer
    assert token.agent?
    assert token.run_token?
    assert token.read_write?
    assert_equal %w[api mcp], token.channel_list
  end

  test "reach: the run token reaches the projects that the agent and the runner's owner share" do
    projects(:side).memberships.create!(user: @fish.user)
    token = run_token(lease)

    Current.set(api_token: token) do
      assert_equal [ @project ], Current.projects.to_a
    end
  end

  test "an agent on a change without a session gets one with its lease, and one with a session keeps it" do
    change = put_on(@project.project_changes.create!(name: "export-csv"))

    lease
    session = change.reload.agent_session_id
    assert_match(/\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/, session)

    lease
    assert_equal session, change.reload.agent_session_id
  end

  # One lease per agent

  test "leased to another runner: refused with agent_leased, naming that runner and since when, and Fish keeps its lease" do
    first = lease(@laptop)

    error = assert_raises(AgentLease::Refused) { lease(@desktop) }

    assert_equal :agent_leased, error.code
    assert_equal "laptop", error.details[:runner]
    assert_equal first.created_at, error.details[:leased_at]
    assert first.reload.live?
    assert run_token(first)
    assert_equal 1, AgentLease.where(agent: @fish.user).count
  end

  test "same runner again: the first lease ends with its run token, and the new one works" do
    first = lease(@laptop)
    second = lease(@laptop)

    assert first.reload.ended?
    assert_nil run_token(first)
    assert second.live?
    assert run_token(second)
  end

  test "a lapsed lease of another runner is ended and replaced" do
    first = lease(@laptop)

    travel 6.minutes do
      second = lease(@desktop)
      assert first.reload.ended?
      assert second.live?
    end
  end

  test "workspace on another runner: refused with workspace_elsewhere, naming it, and no lease is created" do
    change = put_on(@project.project_changes.create!(name: "export-csv"))
    workspace(change, runner: @laptop)

    error = assert_raises(AgentLease::Refused) { lease(@desktop) }

    assert_equal :workspace_elsewhere, error.code
    assert_equal "laptop", error.details[:runner]
    assert_equal 0, AgentLease.count
    assert lease(@laptop).live?
  end

  # Renewing and ending a lease

  test "release: the run token stops, and any runner can lease the agent again" do
    first = lease(@laptop)

    first.end!
    first.end!

    assert_nil run_token(first)
    assert lease(@desktop).live?
  end

  test "lapse: a lease not renewed for the lease window ends on its next check, with its run token" do
    leased = lease
    travel(4.minutes) { leased.renew! }

    travel 8.minutes do
      assert leased.reload.live?
    end

    travel 10.minutes do
      assert_not leased.reload.live?
      assert_not leased.live_or_end!
      assert leased.reload.ended?
      assert_nil run_token(leased)
    end
  end

  test "taken request survives: a lapse changes neither the request nor the change" do
    change = @project.project_changes.create!(name: "export-csv")
    request = ChangeRequest.ask!(change:, kind: "explore", by: @bob)
    leased = lease
    taken = ChangeRequest.take!(project: @project, agent: @fish.user, runner: @laptop)
    assert_equal request, taken

    travel 6.minutes do
      leased.live_or_end!
      assert_equal "taken", request.reload.state
      assert_equal @fish.user, change.reload.agent
      assert change.agent_session_id
    end
  end

  test "agent deleted: its lease ends with its run token" do
    leased = lease

    @fish.delete!

    assert leased.reload.ended?
    assert_nil run_token(leased)
  end

  # Run tokens and the agent's tokens

  test "run tokens are not listed among the agent's tokens" do
    issued = issue_agent_token(@fish, issuer: users(:two))
    lease

    assert_equal [ ApiToken.find_active_by_value(issued) ], @fish.tokens.to_a
  end

  test "run tokens do not count: an agent with 20 tokens issued by people is leased, and a person still cannot issue a 21st" do
    20.times { |index| issue_agent_token(@fish, issuer: @bob, name: "token #{index}") }

    assert lease.live?
    refused = ApiToken.issue_for_agent(@fish, issuer: @bob, name: "21st", access: :read, channels: %w[api])
    assert_not refused.save
    assert refused.errors.of_kind?(:base, :too_many_for_agent)
  end
end
