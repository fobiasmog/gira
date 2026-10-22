require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "valid project: the creator is owner and only member, with the default columns" do
    project = Project.create!(title: "Goalner", short_name: "GOAL", owner: users(:one))

    assert_equal [ users(:one) ], project.members.to_a
    assert project.owned_by?(users(:one))
    assert_equal [ "To Do", "Work", "Done" ], project.statuses.map(&:title)
    assert_equal [ 0, 1, 2 ], project.statuses.map(&:position)
    assert_equal "Done", project.done_status.title
  end

  test "short name format" do
    %w[GOAL G1 ABCDEFGHIJ].each do |short_name|
      assert Project.new(title: "T", short_name: short_name, owner: users(:one)).valid?, short_name
    end
    %w[goal-1 goal G 1GOAL ABCDEFGHIJK GO-AL].each do |short_name|
      assert_not Project.new(title: "T", short_name: short_name, owner: users(:one)).valid?, short_name
    end
  end

  test "title length" do
    assert_not Project.new(title: "", short_name: "GOAL", owner: users(:one)).valid?
    assert_not Project.new(title: "a" * 101, short_name: "GOAL", owner: users(:one)).valid?
  end

  test "task numbers are taken atomically" do
    project = projects(:goal)

    assert_equal [ 1, 2 ], [ project.next_task_number!, project.next_task_number! ]
  end

  # API tokens (spec api-tokens, "Token lifetime and revocation"). two has
  # tokens for goal and side; one has a token for goal.
  test "a member leaving deletes only their tokens for that project" do
    revoked = api_tokens(:two_goal_read_write, :two_goal_read)

    projects(:goal).remove_member!(users(:two))

    revoked.each { |token| assert_not ApiToken.exists?(token.id) }
    assert ApiToken.exists?(api_tokens(:two_side_read_write).id), "the user's tokens for other projects are kept"
    assert ApiToken.exists?(api_tokens(:one_goal_read_write).id), "other members' tokens are kept"
  end

  test "a member removed by the owner loses their tokens, which stay gone after rejoining" do
    project = projects(:goal)
    project.remove_member!(users(:two))
    project.memberships.create!(user: users(:two))

    assert_not users(:two).api_tokens.where(project: project).exists?
    assert ApiToken.exists?(api_tokens(:two_side_read_write).id)
    assert ApiToken.exists?(api_tokens(:one_goal_read_write).id)
  end

  test "archiving deletes every member's tokens for the project" do
    projects(:goal).archive!

    assert_not projects(:goal).api_tokens.exists?
    assert ApiToken.exists?(api_tokens(:two_side_read_write).id), "tokens for other projects are kept"
  end

  test "removing a member takes them out of the project's call" do
    project = projects(:goal)

    assert_enqueued_with(job: CallEvictionJob, args: [ project, users(:two) ]) do
      project.remove_member!(users(:two))
    end
  end

  test "archiving ends the project's call for everybody" do
    project = projects(:goal)

    assert_enqueued_with(job: CallEvictionJob, args: [ project ]) do
      project.archive!
    end
  end
end
