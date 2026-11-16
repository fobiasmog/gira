require "test_helper"

class Api::Projects::MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:goal)
    sign_in_as users(:one)
  end

  test "members are listed with name, email and avatar" do
    get api_project_members_path(@project)

    assert_equal [ "User One", "User Two" ], response.parsed_body.map { |m| m["name"] }
    assert_equal %w[agent avatar_url deleted email_address id name], response.parsed_body.first.keys.sort
    assert_equal [ [ false, false ] ], response.parsed_body.map { |m| m.values_at("agent", "deleted") }.uniq
  end

  # Agents (spec project-membership, "Member list and removal"; spec agents, "Agents in projects")

  test "agents in the list: an agent is listed and marked, a deleted one is not listed" do
    fish = create_agent(@project, name: "Fish")
    create_agent(@project, name: "Owl").delete!

    get api_project_members_path(@project)

    assert_equal [ "Fish", "User One", "User Two" ], response.parsed_body.map { |m| m["name"] }
    entry = response.parsed_body.first
    assert_equal [ fish.user.id, fish.user.email_address, true, false ], entry.values_at("id", "email_address", "agent", "deleted")
    assert entry["avatar_url"].present?
  end

  test "the member list is readable with an agent's token" do
    fish = create_agent(@project, name: "Fish")
    sign_out

    get api_project_members_path(@project), headers: bearer(issue_agent_token(fish, issuer: users(:two), access: :read))

    assert_response :success
    assert_equal [ "Fish", "User One", "User Two" ], response.parsed_body.map { |m| m["name"] }
  end

  test "member removes an agent: it leaves the project, its tasks there are unassigned, and it stays elsewhere" do
    fish = create_agent(@project, name: "Fish")
    projects(:side).memberships.create!(user: fish.user)
    here = @project.tasks.create!(title: "Here", creator: users(:one), assignee: fish.user, status: statuses(:goal_todo))
    there = projects(:side).tasks.create!(title: "There", creator: users(:two), assignee: fish.user, status: projects(:side).first_status)
    sign_in_as users(:two) # a member, not the owner

    delete api_project_member_path(@project, fish.user)

    assert_response :no_content
    assert_not @project.member?(fish.user)
    assert projects(:side).member?(fish.user)
    assert_nil here.reload.assignee_id
    assert_equal fish.user.id, there.reload.assignee_id
    assert_not fish.reload.deleted?
  end

  test "last project: an agent cannot be removed from its only non-archived project" do
    fish = create_agent(@project, name: "Fish")
    archived = Project.create!(title: "Old", short_name: "OLD", owner: users(:one))
    archived.memberships.create!(user: fish.user)
    archived.archive!
    task = @project.tasks.create!(title: "Kept", creator: users(:one), assignee: fish.user, status: statuses(:goal_todo))

    delete api_project_member_path(@project, fish.user)

    assert_response :unprocessable_content
    assert_equal [ "An agent cannot be removed from its only project. Delete it instead." ], response.parsed_body.dig("error", "fields", "base")
    assert @project.member?(fish.user)
    assert_equal fish.user.id, task.reload.assignee_id
  end

  test "a deleted agent cannot be removed from a project" do
    fish = create_agent(@project, name: "Fish")
    projects(:side).memberships.create!(user: fish.user)
    fish.delete!

    delete api_project_member_path(@project, fish.user)

    assert_response :not_found
    assert @project.member?(fish.user)
  end

  test "an agent cannot be removed with a token" do
    fish = create_agent(@project, name: "Fish")
    projects(:side).memberships.create!(user: fish.user)
    sign_out

    delete api_project_member_path(@project, fish.user), headers: bearer("glnr_one_goal_read_write")

    assert_response :forbidden
    assert @project.member?(fish.user)
  end

  test "owner removes a member: access is lost and their tasks become unassigned" do
    task = @project.tasks.create!(number: 1, title: "T", creator: users(:one), assignee: users(:two))

    delete api_project_member_path(@project, users(:two))

    assert_response :no_content
    assert_not @project.member?(users(:two))
    assert_nil task.reload.assignee_id
  end

  test "member tries to remove another member" do
    @project.memberships.create!(user: users(:stranger))
    sign_in_as users(:two)

    delete api_project_member_path(@project, users(:stranger))

    assert_response :forbidden
    assert @project.member?(users(:stranger))
  end

  test "the owner cannot be removed" do
    delete api_project_member_path(@project, users(:one))

    assert_response :forbidden
    assert @project.member?(users(:one))
  end
end
