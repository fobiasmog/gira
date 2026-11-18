require "test_helper"

# Spec comments, "Comment on a change"; add-change-conversation design.md,
# decision 7.
class CommentTest < ActiveSupport::TestCase
  setup do
    @project = projects(:goal)
    @task = @project.tasks.create!(title: "T", creator: users(:one))
    @change = @project.project_changes.create!(name: "export-csv")
  end

  test "a comment belongs to a task or to a change, and takes its project from it" do
    on_task = Comment.create!(task: @task, author: users(:one), body: "On a task")
    on_change = Comment.create!(change: @change, author: users(:one), body: "On a change")
    side = projects(:side).project_changes.create!(name: "theirs")

    assert_equal [ @project.id, @project.id ], [ on_task.project_id, on_change.project_id ]
    assert_equal projects(:side).id, Comment.create!(change: side, author: users(:two), body: "x").project_id
    assert_equal [ on_change ], @change.comments.to_a
  end

  test "both or neither: invalid, and refused by the database" do
    [ { task: @task, change: @change }, {} ].each do |owners|
      comment = Comment.new(author: users(:one), body: "x", **owners)
      assert_not comment.valid?, owners.keys.inspect
      assert comment.errors.of_kind?(:base, :task_or_change)
      assert_raises(ActiveRecord::StatementInvalid) { comment.save!(validate: false) }
    end
  end
end
