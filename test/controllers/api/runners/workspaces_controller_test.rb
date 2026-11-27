require "test_helper"

# Spec agent-workspaces, "Workspace of a change", "Workspace on one machine",
# "Checkpoints", "Workspace in change responses" and "Removing workspaces";
# spec security-baseline, "Deny by default" ("Runner reaching for another
# runner's workspace"); add-runners-and-workspaces design.md, decisions 3
# and 4. goal: one (owner, "Bob") and two.
class Api::Runners::WorkspacesControllerTest < ActionDispatch::IntegrationTest
  PATH = "/home/bob/goalner/workspaces/GOAL/export-csv".freeze
  COMMIT = "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678".freeze

  setup do
    @bob = users(:one)
    @goal = projects(:goal)
    @fish = create_agent(@goal, name: "Fish")
    @laptop = Runner.issue(user: @bob, name: "laptop").tap(&:save!)
    @desktop = Runner.issue(user: @bob, name: "desktop").tap(&:save!)
    @change = @goal.project_changes.create!(name: "export-csv")
    @change.update!(agent: @fish.user, agent_taken_at: Time.current, agent_session_id: SecureRandom.uuid)
  end

  def record(change = @change, runner: @laptop, path: PATH, branch: "export-csv")
    put api_runner_change_workspace_path(change), params: { path:, branch: }, headers: bearer(runner.secret), as: :json
  end

  def report(workspace, runner: @laptop, **params)
    patch api_runner_workspace_path(workspace), params:, headers: bearer(runner.secret), as: :json
  end

  def lease(runner = @laptop) = AgentLease.lease!(agent: @fish, runner:)

  def error = response.parsed_body["error"]

  # Workspace of a change

  test "record: an active workspace on laptop with that path and branch and the base branch main" do
    lease

    record

    assert_response :success
    workspace = @change.reload.workspace
    assert_equal [ @laptop, PATH, "export-csv", "main", "active" ], [ workspace.runner, workspace.path, workspace.branch, workspace.base_branch, workspace.state ]
    assert_equal [ workspace.id, "laptop", nil ], [ response.parsed_body["id"], response.parsed_body.dig("runner", "name"), response.parsed_body["checkpoint"] ]
  end

  test "recorded again: succeeds, and the workspace is unchanged" do
    lease
    record
    first = @change.reload.workspace

    travel 1.minute do
      record
      assert_response :success
      assert_equal first.updated_at, first.reload.updated_at
    end
  end

  test "another path: a validation error, and the workspace keeps its path" do
    lease
    record

    record(path: "/home/bob/elsewhere")

    assert_response :unprocessable_content
    assert error.dig("fields", "path").present?
    assert_equal PATH, @change.reload.workspace.path
  end

  test "no lease, a lapsed or ended one, an archived change or one with no agent on it: 404, and no workspace is recorded" do
    record
    assert_response :not_found

    travel_to(6.minutes.ago) { lease }
    record
    assert_response :not_found

    lease.end!
    record
    assert_response :not_found

    lease
    @change.release_agent!(by: @bob)
    record
    assert_response :not_found

    archived = @goal.project_changes.create!(name: "fix-login", archived_at: Time.current)
    put api_runner_change_workspace_path(archived), params: { path: "/w", branch: "fix-login" }, headers: bearer(@laptop.secret), as: :json
    assert_response :not_found
    assert_equal 0, Workspace.count
  end

  test "a change in a project the runner's owner does not share: 404" do
    side = projects(:side)
    side.memberships.create!(user: @fish.user)
    @change.release_agent!(by: @bob)
    theirs = side.project_changes.create!(name: "theirs")
    theirs.update!(agent: @fish.user, agent_taken_at: Time.current)
    lease

    record(theirs, path: "/w/theirs", branch: "theirs")

    assert_response :not_found
    assert_nil theirs.reload.workspace
  end

  test "path and branch are required texts" do
    lease

    [ { path: "", branch: "export-csv" }, { path: PATH, branch: nil }, { path: [ PATH ], branch: "export-csv" } ].each do |params|
      put api_runner_change_workspace_path(@change), params:, headers: bearer(@laptop.secret), as: :json
      assert_response :unprocessable_content
    end
    assert_nil @change.reload.workspace
  end

  test "released agent: the workspace stays, and Heron is given it on its next take" do
    lease
    record
    @change.release_agent!(by: @bob)
    heron = create_agent(@goal, name: "Heron")
    ChangeRequest.ask!(change: @change, kind: "propose", by: @bob)
    heron_lease = AgentLease.lease!(agent: heron, runner: @laptop)

    post claim_api_project_requests_path(@goal), headers: bearer(heron_lease.run_token_value), as: :json

    taken = response.parsed_body["request"]
    assert_equal [ "laptop", PATH ], [ taken.dig("change", "workspace", "runner", "name"), taken.dig("change", "workspace", "path") ]
  end

  # Workspace on one machine

  test "other runner: a checkpoint or a state for laptop's workspace is 404, and the workspace is unchanged" do
    lease
    record
    workspace = @change.reload.workspace

    report(workspace, runner: @desktop, head_commit: COMMIT, uncommitted: false)
    assert_response :not_found
    @change.archive!
    report(workspace, runner: @desktop, state: "removed")
    assert_response :not_found

    assert_equal [ nil, "active" ], [ workspace.reload.checkpoint_at, workspace.state ]
  end

  # Checkpoints

  test "report: opening the change shows the commit, that changes are uncommitted, and when it was reported" do
    lease
    record

    report(@change.reload.workspace, head_commit: COMMIT, uncommitted: true)
    assert_response :success

    sign_in_as @bob
    get api_project_change_path(@goal, @change)
    checkpoint = response.parsed_body.dig("workspace", "checkpoint")
    assert_equal [ COMMIT, true ], checkpoint.values_at("head_commit", "uncommitted")
    assert checkpoint["at"].present?
  end

  test "a malformed commit or flag: a validation error" do
    lease
    record
    workspace = @change.reload.workspace

    report(workspace, head_commit: "a1b2c3d", uncommitted: true)
    assert_response :unprocessable_content
    assert error.dig("fields", "head_commit").present?
    report(workspace, head_commit: COMMIT, uncommitted: "yes")
    assert_response :unprocessable_content
    assert_nil workspace.reload.checkpoint_at
  end

  # Removing workspaces

  test "to remove, removed and kept" do
    lease
    record
    workspace = @change.reload.workspace
    @change.archive!

    get api_runner_workspaces_path(to_remove: true), headers: bearer(@laptop.secret)
    assert_response :success
    listed = response.parsed_body.sole
    assert_equal [ workspace.id, PATH, "export-csv", "active" ], listed.values_at("id", "path", "branch", "state")
    assert_equal({ "id" => @change.id, "name" => "export-csv", "project" => { "id" => @goal.id, "short_name" => "GOAL" } }, listed["change"])

    get api_runner_workspaces_path(to_remove: true), headers: bearer(@desktop.secret)
    assert_empty response.parsed_body

    report(workspace, state: "kept")
    assert_response :success
    get api_runner_workspaces_path(to_remove: true), headers: bearer(@laptop.secret)
    assert_equal [ "kept" ], response.parsed_body.map { |each| each["state"] }

    report(workspace, state: "removed")
    assert_response :success
    get api_runner_workspaces_path(to_remove: true), headers: bearer(@laptop.secret)
    assert_empty response.parsed_body

    sign_in_as @bob
    get api_project_change_path(@goal, @change)
    assert_equal "removed", response.parsed_body.dig("workspace", "state")
  end

  test "open change: marking its workspace as removed is a validation error, and it stays active" do
    lease
    record

    report(@change.reload.workspace, state: "removed")

    assert_response :unprocessable_content
    assert_equal "active", @change.workspace.reload.state
  end

  test "the list needs to_remove=true" do
    get api_runner_workspaces_path, headers: bearer(@laptop.secret)

    assert_response :unprocessable_content
  end
end
