require "test_helper"

# Spec changes, "Change history"; add-change-conversation design.md,
# decision 4.
class ChangeEventTest < ActiveSupport::TestCase
  setup { @change = projects(:goal).project_changes.create!(name: "export-csv") }

  def event(**attributes) = @change.events.new(actor: users(:one), **attributes)

  test "a phase move names the phase moved to, and an import the paths it brought" do
    move = event(kind: "phase", phase: "exploring").tap(&:save!)
    import = event(kind: "import", paths: %w[proposal.md specs/export/spec.md tasks.md]).tap(&:save!)

    assert_equal [ [ "phase", "exploring", nil, users(:one) ], [ "import", nil, %w[proposal.md specs/export/spec.md tasks.md], users(:one) ] ],
      @change.events.reload.map { |e| [ e.kind, e.phase, e.paths, e.actor ] }
    assert move.created_at.present? && import.created_at.present?
  end

  test "an unknown kind, a phase move without a stored phase, an import without paths: invalid" do
    [ { kind: "comment" }, { kind: "phase" }, { kind: "phase", phase: "done" }, { kind: "phase", phase: "exploring", paths: [ "tasks.md" ] },
      { kind: "import" }, { kind: "import", paths: [] }, { kind: "import", paths: [ "tasks.md" ], phase: "proposed" } ].each do |attributes|
      assert_not event(**attributes).valid?, attributes.inspect
    end
  end

  test "the database refuses an event that mixes the kinds" do
    assert_raises(ActiveRecord::StatementInvalid) { event(kind: "phase", phase: "done").save!(validate: false) }
    assert_raises(ActiveRecord::StatementInvalid) { event(kind: "import", phase: "proposed", paths: [ "tasks.md" ]).save!(validate: false) }
  end

  test "an event needs an actor" do
    assert_not @change.events.new(kind: "phase", phase: "exploring").valid?
  end
end
