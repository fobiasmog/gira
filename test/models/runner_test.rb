require "test_helper"

# Spec agent-runners, "Runners" and "List, rotate and revoke runners";
# add-runners-and-workspaces design.md, decision 1.
class RunnerTest < ActiveSupport::TestCase
  setup do
    @bob = users(:one)
    @project = projects(:goal)
    @fish = create_agent(@project, name: "Fish")
  end

  def create_runner(name = "laptop", user: @bob) = Runner.issue(user:, name:).tap(&:save!)

  test "the secret has the glnr_runner_ prefix and 40 base58 characters, and only its digest is stored" do
    runner = create_runner

    assert_match(/\Aglnr_runner_[1-9A-HJ-NP-Za-km-z]{40}\z/, runner.secret)
    assert_equal runner.secret.last(4), runner.last_characters
    stored = Runner.connection.select_one("SELECT * FROM runners WHERE id = #{runner.id}").values.map(&:to_s)
    assert stored.none? { |value| value.include?(runner.secret) }
    assert_equal runner, Runner.find_active_by_secret(runner.secret)
    assert_nil Runner.find(runner.id).secret
  end

  test "a runner secret is no API token, and an API token is no runner secret" do
    runner = create_runner
    token = issue_agent_token(@fish, issuer: @bob)

    assert_nil ApiToken.find_active_by_value(runner.secret)
    assert_nil Runner.find_active_by_secret(token)
    assert_nil Runner.find_active_by_secret("")
  end

  test "a name of 1 to 100 characters" do
    assert Runner.issue(user: @bob, name: "a" * 100).valid?
    assert_not Runner.issue(user: @bob, name: "").valid?
    assert_not Runner.issue(user: @bob, name: "a" * 101).valid?
  end

  test "runner limit: an eleventh is refused, and a revoked one does not count" do
    10.times { |index| create_runner("machine #{index}") }

    eleventh = Runner.issue(user: @bob, name: "eleventh")
    assert_not eleventh.save
    assert eleventh.errors.of_kind?(:base, :too_many)
    assert create_runner("other", user: users(:two))

    Runner.where(user: @bob).first.revoke!
    assert create_runner("eleventh")
  end

  test "revoke: the secret stops authenticating, its leases end and their run tokens go" do
    runner = create_runner
    lease = AgentLease.lease!(agent: @fish, runner:)

    runner.revoke!

    assert_nil Runner.find_active_by_secret(runner.secret)
    assert lease.reload.ended?
    assert_nil ApiToken.find_active_by_value(lease.run_token_value)
    assert runner.revoked?
  end

  test "rotate: a new secret works, the old one and its leases end, and the workspaces stay" do
    runner = create_runner
    old_secret = runner.secret
    lease = AgentLease.lease!(agent: @fish, runner:)
    change = @project.project_changes.create!(name: "export-csv")
    workspace = Workspace.create!(change:, runner:, path: "/home/bob/goalner/workspaces/GOAL/export-csv", branch: "export-csv", base_branch: "main")

    runner.rotate_secret!

    assert_match(/\Aglnr_runner_/, runner.secret)
    assert_not_equal old_secret, runner.secret
    assert_nil Runner.find_active_by_secret(old_secret)
    assert_equal runner, Runner.find_active_by_secret(runner.secret)
    assert lease.reload.ended?
    assert_nil ApiToken.find_active_by_value(lease.run_token_value)
    assert_equal runner, workspace.reload.runner
    assert_equal "laptop", runner.reload.name
  end

  test "password change: the runners keep working, and their leases go on" do
    runner = create_runner
    lease = AgentLease.lease!(agent: @fish, runner:)

    @bob.update!(password: "a brand new password")

    assert_equal runner, Runner.find_active_by_secret(runner.secret)
    assert lease.reload.live?
    assert ApiToken.find_active_by_value(lease.run_token_value)
  end

  test "last contact is recorded at most once a minute" do
    runner = create_runner
    runner.touch_contact!
    first = runner.reload.last_contact_at

    travel 30.seconds do
      runner.touch_contact!
      assert_equal first, runner.reload.last_contact_at
    end

    travel 61.seconds do
      runner.touch_contact!
      assert_operator runner.reload.last_contact_at, :>, first
    end
  end
end
