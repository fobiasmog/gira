require "test_helper"
require "support/goalner_worker_harness"

# Stopping and restarting the worker, and removing finished workspaces
# (spec agent-worker, "Stop and restart the worker" and "Remove finished
# workspaces"; add-runners-and-workspaces design.md, decision 6).
class GoalnerWorkerRestartTest < ActiveSupport::TestCase
  include GoalnerWorkerHarness

  SESSION = "11111111-2222-4333-8444-555555555555".freeze
  DETACH_HOOK = "#!/bin/sh\necho \"detached $GOALNER_TEST_DB_SUFFIX\" >> \"$GOALNER_WORKER_HOME_MARKS/detach.log\"\n".freeze

  def workspace_path(change = "export-csv") = File.join(workspaces_root, "TEST", change)

  def marks = File.join(@tmp, "marks").tap { |path| FileUtils.mkdir_p(path) }

  # Stop and restart the worker

  test "Ctrl-C and start again: the worker stops the run, releases its lease and exits 0, and the next one resumes the session with the interrupted note" do
    configure
    modes("hang", "finish")
    give_request(12)
    first = start_worker(agent_id.to_s)
    wait_until("the run") { fake_calls.any? }

    assert_equal 0, stop_worker(first, "INT")
    assert_not alive?(fake_calls.first["pid"])
    assert_equal 1, @api.calls("DELETE", %r{/api/runner/leases/1}).size
    assert_nil @api.live_lease
    assert_equal 12, @api.taken["id"]

    second = start_worker(agent_id.to_s)
    wait_until("the request to be finished") { @api.finished.any? }
    assert_equal 0, stop_worker(second, "TERM")

    resumed = fake_calls.last
    assert_equal SESSION, option(resumed, "--resume")
    assert_match(/Your previous run of this request was interrupted/, prompt_of(resumed))
    assert_match(/"id": 12/, prompt_of(resumed))
  end

  test "killed with its run left going: the next worker leases Fish at once, stops the old run first, and continues the taken request" do
    configure
    modes("hang", "finish")
    give_request(12)
    first = start_worker(agent_id.to_s)
    wait_until("the run") { fake_calls.any? }
    orphan = fake_calls.first["pid"]

    stop_process(first, "KILL")
    @workers.delete(first)
    assert alive?(orphan)

    second = start_worker(agent_id.to_s)
    wait_until("the request to be finished") { @api.finished.any? }
    assert_equal 0, stop_worker(second)

    assert_not alive?(orphan)
    assert_equal 2, @api.leases.size
    assert_match(/A run left by a worker that was killed is still going \(pid #{orphan}\); stopping it first/, output_of(second))
    assert_equal SESSION, option(fake_calls.last, "--resume")
  end

  # Remove finished workspaces

  def archived_workspace(change: "export-csv", change_id: 42, path: workspace_path(change))
    FileUtils.mkdir_p(File.dirname(path))
    git(@clone, "worktree", "add", "-q", "-b", change, path, "main")
    @api.workspaces[change_id] = { "id" => change_id + 1000, "runner" => { "name" => "laptop" }, "path" => path, "branch" => change, "base_branch" => "main",
      "state" => "active", "checkpoint" => nil, "to_remove" => true, "change" => { "id" => change_id, "name" => change, "project" => StandInGoalner::PROJECT } }
  end

  def start_and_settle
    pid = start_worker(agent_id.to_s, env: { "GOALNER_WORKER_HOME_MARKS" => marks })
    wait_until("a take") { @api.claims.any? }
    assert_equal 0, stop_worker(pid)
  end

  test "at start: an archived change's clean worktree is removed after the detach hook, its branch stays, and the workspace is removed" do
    @clone = create_clone(files: { "bin/goalner-detach" => [ DETACH_HOOK, 0o755 ] })
    configure
    archived_workspace

    start_and_settle

    assert_not File.exist?(workspace_path)
    assert git(@clone, "branch", "--list", "export-csv").include?("export-csv")
    assert_equal "removed", @api.workspaces[42]["state"]
    assert_equal [ "detached c42" ], File.readlines(File.join(marks, "detach.log"), chomp: true)
  end

  test "uncommitted changes: the worktree stays in place, and the workspace is kept" do
    @clone = create_clone(files: { "bin/goalner-detach" => [ DETACH_HOOK, 0o755 ] })
    configure
    archived_workspace(change: "fix-login", change_id: 43)
    File.write(File.join(workspace_path("fix-login"), "notes.md"), "not committed\n")

    start_and_settle

    assert File.exist?(File.join(workspace_path("fix-login"), "notes.md"))
    assert_equal "kept", @api.workspaces[43]["state"]
    assert_not File.exist?(File.join(marks, "detach.log"))
  end

  test "a workspace whose path is gone is marked removed" do
    @clone = create_clone
    configure
    archived_workspace
    git(@clone, "worktree", "remove", workspace_path)

    start_and_settle

    assert_equal "removed", @api.workspaces[42]["state"]
  end

  test "after an archive request finished as done: the change's workspace is removed" do
    @clone = create_clone
    configure
    modes("finish")
    give_request(12, kind: "archive")
    pid = start_worker(agent_id.to_s)

    wait_until("the workspace to be removed") { @api.workspaces[42]&.fetch("state") == "removed" }
    assert_equal 0, stop_worker(pid)
    assert_not File.exist?(workspace_path)
    assert git(@clone, "branch", "--list", "export-csv").include?("export-csv")
  end
end
