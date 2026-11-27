require "test_helper"
require "support/goalner_worker_harness"

# Attaching to the workspace of a request's change (spec agent-worker,
# "Attach to a workspace"; add-runners-and-workspaces design.md, decisions 3
# and 7), against a temporary git repository.
class GoalnerWorkerAttachTest < ActiveSupport::TestCase
  include GoalnerWorkerHarness

  ATTACH_HOOK = "#!/bin/sh\necho \"attached in $(pwd) with $GOALNER_TEST_DB_SUFFIX\" >> \"$GOALNER_WORKER_HOME_MARKS/attach.log\"\n".freeze

  def workspace_path = File.join(workspaces_root, "TEST", "export-csv")

  def marks = File.join(@tmp, "marks").tap { |path| FileUtils.mkdir_p(path) }

  # Runs the worker until request 12 is finished or failed.
  def work_on_request(clone, env: {})
    configure(clones: { "TEST" => clone })
    give_request(12)
    pid = start_worker(agent_id.to_s, env: { "GOALNER_WORKER_HOME_MARKS" => marks }.merge(env))
    wait_until("request 12 to be finished") { @api.finished.any? }
    assert_equal 0, stop_worker(pid)
    pid
  end

  test "first request of a change: a worktree on a new branch from main, recorded, and the attach hook run there" do
    clone = create_clone(files: { "bin/goalner-attach" => [ ATTACH_HOOK, 0o755 ] })

    work_on_request(clone)

    assert File.directory?(workspace_path)
    assert_equal "export-csv", git(workspace_path, "rev-parse", "--abbrev-ref", "HEAD").strip
    assert_equal git(clone, "rev-parse", "main"), git(workspace_path, "rev-parse", "HEAD")
    recorded = @api.calls("PUT", %r{/api/runner/changes/42/workspace}).sole
    assert_equal({ "path" => workspace_path, "branch" => "export-csv" }, recorded[:params])
    assert_equal StandInGoalner::SECRET, recorded[:token]
    assert_equal [ "attached in #{workspace_path} with c42" ], File.readlines(File.join(marks, "attach.log"), chomp: true)
    assert_equal workspace_path, File.realpath(fake_calls.sole["cwd"])
    assert_equal [ "done" ], @api.finished.map { |finished| finished["outcome"] }
  end

  test "after a crash before recording: the existing worktree is used and recorded, and the request runs" do
    clone = create_clone
    FileUtils.mkdir_p(File.dirname(workspace_path))
    git(clone, "worktree", "add", "-q", "-b", "export-csv", workspace_path, "main")
    File.write(File.join(workspace_path, "draft.md"), "kept\n")

    work_on_request(clone)

    assert_equal "kept\n", File.read(File.join(workspace_path, "draft.md"))
    assert_equal 1, @api.calls("PUT", %r{/workspace}).size
    assert_equal 1, fake_calls.size
  end

  test "branch taken: finished as failed naming the branch, and no worktree is created" do
    clone = create_clone
    git(clone, "branch", "export-csv")

    work_on_request(clone)

    assert_equal "failed", @api.finished.sole["outcome"]
    assert_match(/branch `export-csv` already exists/, @api.finished.sole["comment"])
    assert_not File.exist?(workspace_path)
    assert_empty fake_calls
    assert_empty @api.calls("PUT", %r{/workspace})
  end

  test "a path that holds something else, or a base branch missing from the clone: finished as failed" do
    clone = create_clone
    FileUtils.mkdir_p(workspace_path)

    work_on_request(clone)
    assert_match(/exists, and it is no worktree of the branch `export-csv`/, @api.finished.sole["comment"])

    FileUtils.rm_rf(workspace_path)
    git(clone, "branch", "-m", "main", "trunk")
    @api.finished.clear
    work_on_request(clone)
    assert_match(/base branch `main` does not exist/, @api.finished.sole["comment"])
    assert_empty fake_calls
  end

  test "attach hook fails: finished as failed with the end of its output, and no Claude Code process started" do
    clone = create_clone(files: { "bin/goalner-attach" => [ "#!/bin/sh\necho 'bundle install failed: no network'\nexit 1\n", 0o755 ] })

    work_on_request(clone)

    assert_equal "failed", @api.finished.sole["outcome"]
    assert_match(/attach hook `bin\/goalner-attach` failed.*bundle install failed: no network/m, @api.finished.sole["comment"])
    assert_empty fake_calls
  end

  test "an active workspace whose files are gone: its worktree is created again from its branch, with the files lost note" do
    clone = create_clone
    FileUtils.mkdir_p(File.dirname(workspace_path))
    git(clone, "worktree", "add", "-q", "-b", "export-csv", workspace_path, "main")
    @api.workspaces[42] = { "id" => 1042, "runner" => { "name" => "laptop" }, "path" => workspace_path, "branch" => "export-csv", "base_branch" => "main", "state" => "active", "checkpoint" => nil }
    FileUtils.rm_rf(workspace_path)

    work_on_request(clone)

    assert File.directory?(workspace_path)
    assert_match(/The workspace's files were lost/, prompt_of(fake_calls.sole))
    assert_empty @api.calls("PUT", %r{/workspace})
  end

  test "an active workspace whose branch is gone: finished as failed" do
    clone = create_clone
    @api.workspaces[42] = { "id" => 1042, "runner" => { "name" => "laptop" }, "path" => workspace_path, "branch" => "export-csv", "base_branch" => "main", "state" => "active", "checkpoint" => nil }

    work_on_request(clone)

    assert_match(/branch `export-csv` of this change's workspace no longer exists/, @api.finished.sole["comment"])
    assert_empty fake_calls
  end
end
