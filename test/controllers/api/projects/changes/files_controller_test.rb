require "test_helper"

# Spec openspec-changes, "Files of a change"; add-change-conversation
# design.md, decision 5.
class Api::Projects::Changes::FilesControllerTest < ActionDispatch::IntegrationTest
  TEXT = "## 1. Export\n\n- [ ] 1.1 Add the endpoint\n"
  PROPOSAL = "# Proposal\n\n## Why\n\nPeople want CSV.  \n\n| a | b |\n|---|---|\n"

  setup do
    @project = projects(:goal)
    sign_in_as users(:one)
  end

  def import(name = "export-csv", **files)
    Change::Import.new(project: @project, user: users(:one), name:, artifacts: { "tasks" => TEXT, **files.transform_keys(&:to_s) }).run!.change
  end

  def read(ref, path, headers: {}) = get(api_project_change_file_path(@project, ref, path:), headers:)

  test "files stored: opening lists them, and reading one returns it exactly as sent" do
    import(proposal: PROPOSAL, design: "# Design\n", specs: { "export" => "## ADDED Requirements\n" })

    get api_project_change_path(@project, "export-csv")
    assert_equal %w[proposal.md design.md specs/export/spec.md], response.parsed_body["files"].map { |file| file["path"] }

    read("export-csv", "proposal.md")
    assert_response :success
    assert_equal({ "path" => "proposal.md", "text" => PROPOSAL }, response.parsed_body)

    read("export-csv", "specs/export/spec.md")
    assert_equal "## ADDED Requirements\n", response.parsed_body["text"]
  end

  test "a file no longer sent: 404" do
    change = import(proposal: PROPOSAL, design: "# Design\n")
    Change::Import.new(project: @project, user: users(:one), name: "export-csv", artifacts: { "tasks" => change.tasks_text, "proposal" => PROPOSAL }).run!

    read("export-csv", "design.md")
    assert_response :not_found
  end

  test "an unknown path, tasks.md, no path, or a change that is not there: 404" do
    change = import(proposal: PROPOSAL)
    foreign = projects(:side).project_changes.create!(name: "theirs")
    foreign.files.create!(path: "proposal.md", text: "secret")

    [ [ "export-csv", "notes.md" ], [ "export-csv", "tasks.md" ], [ "export-csv", "../proposal.md" ], [ "export-csv", "" ],
      [ "no-such-change", "proposal.md" ], [ foreign.id, "proposal.md" ] ].each do |ref, path|
      read(ref, path)
      assert_response :not_found, [ ref, path ].inspect
    end
    get api_project_change_file_path(@project, change)
    assert_response :not_found
    assert_not_includes response.body, "secret"
  end

  test "archived change: a read-only token reads its proposal by the change's id" do
    change = import("add-labels", proposal: PROPOSAL)
    change.archive!
    sign_out

    read(change.id, "proposal.md", headers: { "Authorization" => "Bearer glnr_two_goal_read" })

    assert_response :success
    assert_equal PROPOSAL, response.parsed_body["text"]
    read("add-labels", "proposal.md", headers: { "Authorization" => "Bearer glnr_two_goal_read" })
    assert_response :not_found
  end
end
