require "test_helper"

# Spec agent-workspaces, "Workspace of a change", "Workspace on one machine",
# "Checkpoints" and "Removing workspaces"; add-runners-and-workspaces
# design.md, decision 3.
class WorkspaceTest < ActiveSupport::TestCase
  PATH = "/home/bob/goalner/workspaces/GOAL/export-csv".freeze
  COMMIT = "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678".freeze

  setup do
    @bob = users(:one)
    @project = projects(:goal)
    @change = @project.project_changes.create!(name: "export-csv")
    @laptop = Runner.issue(user: @bob, name: "laptop").tap(&:save!)
    @desktop = Runner.issue(user: @bob, name: "desktop").tap(&:save!)
  end

  def record(runner = @laptop, path: PATH, branch: "export-csv", change: @change) = Workspace.record!(change:, runner:, path:, branch:)

  def savepoint(&) = ActiveRecord::Base.transaction(requires_new: true, &)

  test "the database refuses a second workspace of one change, and an unknown state" do
    workspace = record
    assert_raises(ActiveRecord::RecordNotUnique) do
      savepoint { Workspace.create!(change: @change, runner: @desktop, path: "/elsewhere", branch: "export-csv", base_branch: "main") }
    end
    assert_raises(ActiveRecord::StatementInvalid) { savepoint { workspace.update_column(:state, "lost") } }
  end

  # Workspace of a change

  test "record: the change has an active workspace on the runner, with its path, branch and the change's base branch" do
    workspace = record

    assert_equal @change.reload.workspace, workspace
    assert workspace.active?
    assert_equal [ @laptop, PATH, "export-csv", "main" ], [ workspace.runner, workspace.path, workspace.branch, workspace.base_branch ]
    assert_nil workspace.checkpoint_at
  end

  test "recorded again: the same path and branch succeed and change nothing" do
    workspace = record

    travel 1.minute do
      assert_equal workspace, record
      assert_equal workspace.updated_at, workspace.reload.updated_at
    end
  end

  test "another path or branch: refused with a validation error, and the workspace keeps its path" do
    record

    error = assert_raises(ActiveRecord::RecordInvalid) { record(path: "/home/bob/elsewhere") }
    assert error.record.errors.of_kind?(:path, :fixed)
    error = assert_raises(ActiveRecord::RecordInvalid) { record(branch: "other") }
    assert error.record.errors.of_kind?(:branch, :fixed)
    assert_equal PATH, @change.reload.workspace.path
  end

  test "a path of 1 to 1,000 characters and a branch are required" do
    assert_raises(ActiveRecord::RecordInvalid) { record(path: "") }
    assert_raises(ActiveRecord::RecordInvalid) { record(path: "/#{'a' * 1000}") }
    assert_raises(ActiveRecord::RecordInvalid) { record(branch: "") }
    assert record(path: "/#{'a' * 999}")
  end

  test "released agent: the workspace stays with the change" do
    fish = create_agent(@project, name: "Fish").user
    @change.update!(agent: fish, agent_taken_at: Time.current, agent_session_id: SecureRandom.uuid)
    workspace = record

    @change.release_agent!(by: @bob)

    assert_equal workspace, @change.reload.workspace
    assert workspace.reload.active?
  end

  # Workspace on one machine

  test "other runner: recording it is not found, and the workspace is unchanged" do
    record

    assert_raises(ActiveRecord::RecordNotFound) { record(@desktop) }
    assert_equal @laptop, @change.reload.workspace.runner
  end

  # Checkpoints

  test "report: the latest checkpoint is kept with its time" do
    workspace = record

    workspace.checkpoint!(head_commit: COMMIT, uncommitted: true)
    travel 1.minute do
      workspace.checkpoint!(head_commit: COMMIT.upcase, uncommitted: false)
    end

    workspace.reload
    assert_equal COMMIT, workspace.head_commit
    assert_equal false, workspace.uncommitted
    assert workspace.checkpoint_at > 30.seconds.from_now
  end

  test "a malformed commit or a missing flag is refused, and a workspace that is not active takes no checkpoint" do
    workspace = record

    assert_raises(ActiveRecord::RecordInvalid) { workspace.checkpoint!(head_commit: "a1b2c3d", uncommitted: false) }
    assert_raises(ActiveRecord::RecordInvalid) { workspace.reload.checkpoint!(head_commit: COMMIT, uncommitted: nil) }

    @change.archive!
    workspace.reload.mark!("kept")
    error = assert_raises(ActiveRecord::RecordInvalid) { workspace.checkpoint!(head_commit: COMMIT, uncommitted: false) }
    assert error.record.errors.of_kind?(:base, :not_active)
    assert_nil workspace.reload.checkpoint_at
  end

  # Removing workspaces

  test "to remove: active and kept workspaces of archived changes, on their runner" do
    archived = record
    open = record(change: @project.project_changes.create!(name: "add-tags"), path: "/home/bob/goalner/workspaces/GOAL/add-tags", branch: "add-tags")
    elsewhere = record(@desktop, change: @project.project_changes.create!(name: "fix-login"), path: "/desktop/fix-login", branch: "fix-login")
    @change.archive!
    elsewhere.change.archive!

    assert_equal [ archived ], @laptop.workspaces.to_remove.to_a
    assert_equal [ elsewhere ], @desktop.workspaces.to_remove.to_a
    assert_not_includes Workspace.to_remove, open
  end

  test "removed: final, and no longer to remove" do
    workspace = record
    @change.archive!

    workspace.mark!("removed")
    workspace.mark!("removed")

    assert_equal "removed", workspace.reload.state
    assert_empty @laptop.workspaces.to_remove
    error = assert_raises(ActiveRecord::RecordInvalid) { workspace.mark!("kept") }
    assert error.record.errors.of_kind?(:state, :removed)
    assert_equal "removed", workspace.reload.state
  end

  test "kept: still to remove, until it is removed" do
    workspace = record
    @change.archive!

    workspace.mark!("kept")

    assert_equal "kept", workspace.reload.state
    assert_equal [ workspace ], @laptop.workspaces.to_remove.to_a
    workspace.mark!("removed")
    assert_empty @laptop.workspaces.to_remove
  end

  test "open change: marking its workspace removed or kept is refused, and it stays active" do
    workspace = record

    error = assert_raises(ActiveRecord::RecordInvalid) { workspace.mark!("removed") }
    assert error.record.errors.of_kind?(:base, :change_open)
    assert_raises(ActiveRecord::RecordInvalid) { workspace.mark!("kept") }
    assert_raises(ActiveRecord::RecordInvalid) { workspace.mark!("active") }
    assert workspace.reload.active?
  end
end
