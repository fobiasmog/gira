require "test_helper"

# Spec openspec-changes, "Files of a change"; add-change-conversation
# design.md, decision 5.
class ChangeFileTest < ActiveSupport::TestCase
  setup { @change = projects(:goal).project_changes.create!(name: "export-csv") }

  def file(path, text = "# #{path}") = @change.files.new(path:, text:)

  test "a file is proposal.md, design.md or the spec.md of a capability path" do
    %w[proposal.md design.md specs/export/spec.md specs/identity/user-auth/spec.md specs/v2/spec.md].each do |path|
      assert file(path).valid?, path
    end
  end

  test "any other path is invalid" do
    [ "tasks.md", "notes.md", "specs/spec.md", "specs/../secrets/spec.md", "specs/Export/spec.md", "specs/export//spec.md",
      "specs/export/other.md", "/proposal.md", "specs/a--b/spec.md", "specs/export/spec.md/x", nil ].each do |path|
      record = file(path)
      assert_not record.valid?, path.inspect
      assert record.errors.of_kind?(:path, :invalid), path.inspect
    end
  end

  test "a path is unique per change, and may repeat in another change" do
    file("proposal.md").save!

    duplicate = file("proposal.md")
    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:path, :taken)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
    assert projects(:goal).project_changes.create!(name: "fix-login").files.create!(path: "proposal.md", text: "x")
  end

  test "the text is at most 100,000 characters, and may be empty" do
    assert file("design.md", "a" * 100_000).valid?
    assert file("design.md", "").valid?
    assert_not file("design.md", "a" * 100_001).valid?
    assert file("design.md", nil).invalid?
  end

  test "files are ordered proposal, design, then specs by path" do
    %w[specs/identity/user-auth/spec.md design.md specs/export/spec.md specs/a-b/spec.md proposal.md specs/a/b/spec.md].each do |path|
      file(path).save!
    end

    assert_equal %w[proposal.md design.md specs/a-b/spec.md specs/a/b/spec.md specs/export/spec.md specs/identity/user-auth/spec.md],
      @change.files.in_order.pluck(:path)
  end
end
