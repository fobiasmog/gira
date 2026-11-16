require "test_helper"

# Spec openspec-changes, "OpenSpec changes in a project".
class OpenspecChangeTest < ActiveSupport::TestCase
  test "a change is named by groups of lowercase letters and digits joined by single hyphens" do
    %w[add-agents a fix-2fa v2 add-mcp-oauth].each do |name|
      assert build_change(name:).valid?, name
    end
    assert build_change(name: "a" * 100).valid?
  end

  test "other names are invalid" do
    [ "Add Agents", "add_agents", "add--agents", "-add", "add-", "add agents", "", "a" * 101, "добавить" ].each do |name|
      change = build_change(name:)
      assert_not change.valid?, name
      assert change.errors.include?(:name), name
    end
  end

  test "a name is unique within its project, not across projects" do
    build_change(name: "add-agents").save!

    assert build_change(name: "add-agents", project: projects(:side), imported_by: users(:two)).valid?
    duplicate = build_change(name: "add-agents")
    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:name, :taken)
  end

  test "tasks belong to a change, and a project's changes go with it" do
    change = build_change(name: "add-labels")
    change.save!
    task = projects(:goal).tasks.create!(title: "add-labels: 1. Model", creator: users(:one), openspec_change: change)

    assert_equal [ task ], change.tasks.to_a
    assert_equal change, task.reload.openspec_change
    assert_nil projects(:goal).tasks.create!(title: "Ordinary", creator: users(:one)).openspec_change
  end

  private
    def build_change(name:, project: projects(:goal), imported_by: users(:one))
      milestone = project.milestones.create!(title: name.presence&.first(100) || "x")
      OpenspecChange.new(project:, name:, milestone:, imported_by:, imported_at: Time.current)
    end
end
