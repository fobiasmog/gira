require "test_helper"

class Api::Projects::MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:goal)
    sign_in_as users(:one)
  end

  test "members are listed with name, email and avatar" do
    get api_project_members_path(@project)

    assert_equal [ "User One", "User Two" ], response.parsed_body.map { |m| m["name"] }
    assert_equal %w[avatar_url email_address id name], response.parsed_body.first.keys.sort
  end

  test "owner removes a member: access is lost and their tasks become unassigned" do
    task = @project.tasks.create!(number: 1, title: "T", creator: users(:one), assignee: users(:two))

    assert_enqueued_with(job: CallEvictionJob, args: [ @project, users(:two) ]) do
      delete api_project_member_path(@project, users(:two))
    end

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
