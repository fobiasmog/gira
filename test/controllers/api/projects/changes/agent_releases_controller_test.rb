require "test_helper"

# Spec change-requests, "Agent of a change" and "Release an agent"; spec
# changes, "Create a change" and "Change history"; add-change-requests
# design.md, decisions 2, 4 and 6.
class Api::Projects::Changes::AgentReleasesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:goal)
    @fish = create_agent(@project, name: "Fish").user
    @heron = create_agent(@project, name: "Heron").user
    sign_in_as users(:one)
  end

  def create_change(name, **attributes) = @project.project_changes.create!(name:, **attributes)

  def pick(ref, agent)
    patch api_project_change_path(@project, ref), params: { agent: }, as: :json
  end

  def agent_of(body) = body["agent"]&.then { |agent| [ agent.dig("user", "name"), agent["on"] ] }

  # Agent of a change

  test "with an agent: 201, in Idea with Fish picked" do
    post api_project_changes_path(@project), params: { name: "add-tags", idea: "Tags on tasks.", agent: @fish.id }, as: :json

    assert_response :created
    assert_equal [ "idea", [ "Fish", false ] ], [ response.parsed_body["phase"], agent_of(response.parsed_body) ]
    assert_nil response.parsed_body["request"]
    change = @project.project_changes.find_by!(name: "add-tags")
    assert_equal [ @fish, nil ], [ change.agent, change.agent_taken_at ]
    assert_empty change.requests
  end

  test "without an agent: none" do
    post api_project_changes_path(@project), params: { name: "export-csv" }, as: :json

    assert_response :created
    assert_nil response.parsed_body["agent"]
  end

  test "move to another agent, and back to any free agent" do
    create_change("add-tags", agent: @fish)

    pick "add-tags", @heron.id
    assert_response :ok
    assert_equal [ "Heron", false ], agent_of(response.parsed_body)

    pick "add-tags", nil
    assert_response :ok
    assert_nil response.parsed_body["agent"]
  end

  test "picking does not ask for a step, and the idea stays editable in Idea" do
    create_change("add-tags")

    patch api_project_change_path(@project, "add-tags"), params: { agent: @fish.id, idea: "Tags on tasks." }, as: :json

    assert_response :ok
    assert_equal [ "Tags on tasks.", "idea", nil ], response.parsed_body.values_at("idea", "phase", "request")
  end

  test "agent on the change: 422 on the agent, and Fish stays on" do
    change = create_change("export-csv", agent: @fish)
    change.update!(agent_taken_at: Time.current)

    pick "export-csv", @heron.id

    assert_response :unprocessable_content
    assert response.parsed_body.dig("error", "fields", "agent").present?
    assert_equal [ @fish, true ], [ change.reload.agent, change.agent_on? ]
  end

  test "not an agent, a deleted agent, an unknown user or not an id: 422 on the agent, the change unchanged" do
    create_change("add-tags")
    owl = create_agent(@project, name: "Owl").tap(&:delete!).user

    [ users(:two).id, owl.id, 0, "Fish", { id: 1 } ].each do |agent|
      pick "add-tags", agent
      assert_response :unprocessable_content
      assert response.parsed_body.dig("error", "fields", "agent").present?, agent.inspect
    end
    post api_project_changes_path(@project), params: { name: "export-csv", agent: users(:two).id }, as: :json
    assert_response :unprocessable_content
    assert_nil @project.project_changes.find_by!(name: "add-tags").agent
    assert_not @project.project_changes.exists?(name: "export-csv")
  end

  # Release an agent

  test "release while waiting for people: no agent, and the history lists the member releasing Fish" do
    change = create_change("export-csv", phase: "exploring", agent: @fish)
    change.update!(agent_taken_at: Time.current)

    post api_project_change_agent_release_path(@project, "export-csv"), as: :json

    assert_response :ok
    assert_nil response.parsed_body["agent"]
    release = response.parsed_body["history"].last
    assert_equal [ "release", "User One", "Fish" ], [ release["kind"], release.dig("actor", "name"), release.dig("agent", "name") ]
    post api_project_change_requests_path(@project, "export-csv"), params: { kind: "propose" }, as: :json
    assert_equal "export-csv", ChangeRequest.take!(project: @project, agent: @heron).change.name
  end

  test "release during a step: the request is cancelled by the member, and Fish's next take does not return it" do
    change = create_change("export-csv", phase: "proposed")
    ChangeRequest.ask!(change:, kind: "implement", by: users(:one))
    request = ChangeRequest.take!(project: @project, agent: @fish)

    post api_project_change_agent_release_path(@project, change.id), as: :json

    assert_response :ok
    assert_equal [ "cancelled", users(:one) ], [ request.reload.state, request.finished_by ]
    assert_nil ChangeRequest.take!(project: @project, agent: @fish)
    history = response.parsed_body["history"].last(2).map { |entry| entry.values_at("kind", "state") }
    assert_equal [ [ "request", "cancelled" ], [ "release", nil ] ], history
  end

  test "a change with no agent is left as it is" do
    create_change("export-csv")

    assert_no_difference(-> { ChangeEvent.count }) do
      post api_project_change_agent_release_path(@project, "export-csv"), as: :json
    end
    assert_response :ok
  end

  test "an archived change or a change of another project: refused" do
    archived = create_change("export-csv", agent: @fish).tap { |change| change.update!(agent_taken_at: Time.current) }
    archived.archive!(by: users(:one))

    post api_project_change_agent_release_path(@project, archived.id), as: :json
    assert_response :unprocessable_content

    foreign = projects(:side).project_changes.create!(name: "theirs")
    post api_project_change_agent_release_path(projects(:side), foreign.id), as: :json
    assert_response :not_found
  end
end
