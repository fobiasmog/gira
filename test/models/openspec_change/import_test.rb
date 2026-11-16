require "test_helper"

# Spec openspec-changes: "Import a change", "Cards and subtasks of a change",
# "Goalner keys in the tasks text", "Import again" and "Limits of a change";
# add-openspec-changes design.md, decisions 3 to 5.
class OpenspecChange::ImportTest < ActiveSupport::TestCase
  LABELS = <<~MD
    # Tasks

    ## 1. Model

    - [ ] 1.1 Add the table
    - [ ] 1.2 Add the model
    - [ ] 1.3 Add the validations

    ## 2. API

    - [ ] 2.1 Add the routes
    - [ ] 2.2 Add the controller
    - [ ] 2.3 Add the docs
  MD

  setup { @project = projects(:goal) }

  def import(text, name: "add-labels", project: @project, user: users(:one), artifacts: nil)
    OpenspecChange::Import.new(project:, user:, name:, artifacts: artifacts || { "tasks" => text }).run!
  end

  def refusal(**options, &block)
    error = assert_raises(ActiveRecord::RecordInvalid, &block)
    error.record.errors
  end

  def counts = [ -> { Task.count }, -> { Milestone.count }, -> { OpenspecChange.count } ]

  def task(key) = @project.tasks.find_by_ref!(key)

  def keys_in(text) = text.scan(/goalner:(TEST|GOAL)-(\d+)/).map { |_, number| number.to_i }

  # First import

  test "a first import creates the change, its milestone, cards and subtasks" do
    result = import(LABELS)
    change = result.change

    assert result.created
    assert_equal "add-labels", change.name
    assert_equal "add-labels", change.milestone.title
    assert_equal users(:one), change.imported_by
    assert_not_nil change.imported_at

    cards = change.tasks.roots.order(:position)
    assert_equal [ "add-labels: 1. Model", "add-labels: 2. API" ], cards.map(&:title)
    assert_equal [ [ "1.1 Add the table", "1.2 Add the model", "1.3 Add the validations" ],
                   [ "2.1 Add the routes", "2.2 Add the controller", "2.3 Add the docs" ] ], cards.map { |card| card.subtasks.map(&:title) }
    assert cards.all? { |card| card.milestone == change.milestone }
    assert change.tasks.where.not(parent_id: nil).all? { |subtask| subtask.milestone_id.nil? }
    assert change.tasks.all? { |task| task.creator == users(:one) && task.assignee_id.nil? }
    assert change.tasks.all? { |task| task.status == statuses(:goal_todo) }
    assert_equal [ 0, 1 ], cards.map(&:position)
    assert_match %r{\AOpenSpec change `add-labels`, section "1. Model": `openspec/changes/add-labels/`\z}, cards.first.description
  end

  test "the returned text marks every heading and item with its key, and is otherwise the text as sent" do
    change = import(LABELS).change
    card = change.tasks.roots.find_by!(title: "add-labels: 1. Model")
    table = card.subtasks.first

    assert_includes change.tasks_text, "## 1. Model <!-- goalner:#{card.key} -->\n"
    assert_includes change.tasks_text, "- [ ] 1.1 Add the table <!-- goalner:#{table.key} -->\n"
    assert_equal LABELS, change.tasks_text.gsub(/ <!-- goalner:GOAL-\d+ -->/, "")
    assert_equal 8, keys_in(change.tasks_text).size
  end

  test "new cards join the active sprint" do
    sprint = @project.sprints.create!(title: "Openspec integration", starts_on: Date.current, ends_on: 1.week.from_now)
    sprint.activate!

    change = import(LABELS).change

    assert change.tasks.roots.all? { |card| card.sprint == sprint }
    assert change.tasks.where.not(parent_id: nil).all? { |subtask| subtask.sprint_id.nil? }
  end

  test "without an active sprint, new cards stay outside sprints" do
    @project.sprints.create!(title: "Planned", starts_on: Date.current, ends_on: 1.week.from_now)

    assert import(LABELS).change.tasks.all? { |task| task.sprint_id.nil? }
  end

  test "the same name in two projects makes two changes" do
    import(LABELS)
    other = import("## 1. Side\n- [ ] 1.1 Item\n", project: projects(:side), user: users(:two)).change

    assert_equal projects(:side), other.project
    assert_equal 2, OpenspecChange.where(name: "add-labels").count
    assert_equal 6, @project.openspec_changes.find_by!(name: "add-labels").tasks.where.not(parent_id: nil).count
  end

  test "a long item gets a cut title and its whole line in the description" do
    line = "1.1 #{"word " * 60}end"
    subtask = import("## 1. Long\n- [ ] #{line}\n").change.tasks.where.not(parent_id: nil).first

    assert subtask.title.end_with?("…")
    assert_operator subtask.title.length, :<=, 255
    assert_equal line, subtask.description
  end

  test "items before the first heading go on the change's Tasks card, found again on re-import" do
    change = import("- [ ] Write the docs\n\n## 1. Model\n- [ ] 1.1 Table\n").change
    loose = change.tasks.roots.find_by!(title: "add-labels: Tasks")

    again = import(change.tasks_text + "- [ ] 1.2 Model\n").change

    assert_equal [ loose ], again.tasks.kept.roots.where(title: "add-labels: Tasks").to_a
    assert_equal [ "Write the docs" ], loose.subtasks.map(&:title)
  end

  # Refusals (task 3.1)

  test "an invalid name is refused and nothing is created" do
    assert_no_difference counts do
      assert refusal { import(LABELS, name: "Add Agents") }.include?(:name)
      assert refusal { import(LABELS, name: "a" * 101) }.include?(:name)
    end
  end

  test "artifacts other than tasks are refused" do
    errors = refusal { import(nil, artifacts: { "tasks" => LABELS, "proposal" => "# Why" }) }

    assert_equal [ "Proposal is not an artifact Goalner imports" ], errors.full_messages_for(:proposal)
    assert_equal 0, OpenspecChange.count
  end

  test "the tasks text is required and limited to 100,000 characters" do
    assert refusal { import(nil, artifacts: {}) }.include?(:tasks)
    assert refusal { import(nil, artifacts: { "tasks" => 3 }) }.include?(:tasks)
    assert refusal { import("x" * 100_001) }.of_kind?(:tasks, :too_long)
  end

  test "more than 50 sections or 500 items are refused" do
    assert_no_difference counts do
      sections = (1..51).map { |n| "## #{n}. S\n- [ ] #{n}.1 I\n" }.join
      assert_match(/51 sections/, refusal { import(sections) }.full_messages.join)

      items = "## 1. Many\n" + (1..501).map { |n| "- [ ] 1.#{n} I\n" }.join
      assert_match(/501 items/, refusal { import(items) }.full_messages.join)
    end
  end

  test "an item without a title is refused, naming its line" do
    assert_equal [ "Tasks line 3: the item has no title" ], refusal { import("## 1. A\n- [ ] 1.1 B\n- [ ]\n") }.full_messages
  end

  test "a mark of another change is refused, naming its line, and nothing changes" do
    agents = import("## 1. Agents\n- [ ] 1.1 Model\n", name: "add-agents").change
    foreign = agents.tasks.where.not(parent_id: nil).first

    assert_no_difference counts do
      errors = refusal { import("## 1. Model\n- [ ] 1.1 Table <!-- goalner:#{foreign.key} -->\n") }
      assert_equal [ "Tasks line 2: the mark names #{foreign.key}, which does not belong to this change" ], errors.full_messages
    end
  end

  test "a mark of an ordinary task, or of no task, is refused" do
    ordinary = @project.tasks.create!(title: "Ordinary", creator: users(:one))

    assert_match(/does not belong to this change/, refusal { import("## 1. A <!-- goalner:#{ordinary.key} -->\n- [ ] 1.1 B\n") }.full_messages.join)
    assert_match(/line 2: the mark names no task/, refusal { import("## 1. A\n- [ ] 1.1 B <!-- goalner:GOAL-9999 -->\n") }.full_messages.join)
  end

  test "a card's mark on an item, or a subtask's on a heading, is refused" do
    change = import(LABELS).change
    card = change.tasks.roots.first
    subtask = card.subtasks.first

    assert_match(/item's mark names #{card.key}, a card/, refusal { import("## 1. Model\n- [ ] 1.1 Table <!-- goalner:#{card.key} -->\n") }.full_messages.join)
    assert_match(/heading's mark names #{subtask.key}, a subtask/, refusal { import("## 1. Model <!-- goalner:#{subtask.key} -->\n- [ ] 1.1 Table\n") }.full_messages.join)
  end

  test "a mark used twice is refused on its second line" do
    change = import(LABELS).change
    key = change.tasks.where.not(parent_id: nil).first.key

    errors = refusal { import("## 1. Model\n- [ ] 1.1 A <!-- goalner:#{key} -->\n- [ ] 1.2 B <!-- goalner:#{key} -->\n") }
    assert_equal [ "Tasks line 3: the mark of #{key} is already on line 2" ], errors.full_messages
  end

  # Import again (task 3.2)

  test "importing the returned text again creates nothing and changes nothing" do
    first = import(LABELS)

    assert_no_difference counts do
      again = import(first.change.tasks_text)
      assert_not again.created
      assert_equal first.change.tasks_text, again.change.tasks_text
    end
  end

  test "a renumbered item keeps its task, assignee and comments" do
    change = import(LABELS).change
    table = change.tasks.find_by!(title: "1.1 Add the table")
    table.update!(assignee: users(:two))
    table.comments.create!(author: users(:two), body: "On it")

    import(change.tasks_text.sub("1.1 Add the table", "1.2 Add the table").sub("1.2 Add the model", "1.3 Add the model"))

    table.reload
    assert_equal "1.2 Add the table", table.title
    assert_equal users(:two), table.assignee
    assert_equal [ "On it" ], table.comments.map(&:body)
  end

  test "the text wins over a title edited in Goalner, and keeps the column, sprint and position" do
    change = import(LABELS).change
    card = change.tasks.roots.find_by!(title: "add-labels: 2. API")
    card.update!(title: "Renamed in Goalner", status: statuses(:goal_work))

    import(change.tasks_text)

    card.reload
    assert_equal "add-labels: 2. API", card.title
    assert_equal statuses(:goal_work), card.status
  end

  test "an item moved under another section becomes a subtask of that section's card" do
    change = import(LABELS).change
    docs = change.tasks.find_by!(title: "2.3 Add the docs")
    model_card = change.tasks.roots.find_by!(title: "add-labels: 1. Model")
    moved = change.tasks_text.lines.partition { |line| line.include?("2.3 Add the docs") }
    text = moved.last.join.sub(/(1\.3 Add the validations[^\n]*\n)/) { "#{$1}#{moved.first.first}" }

    import(text)

    assert_equal model_card, docs.reload.parent
  end

  test "a deleted milestone is recovered, and the cards still carry it" do
    change = import(LABELS).change
    change.milestone.delete!

    import(change.tasks_text)

    assert_not change.milestone.reload.deleted?
    assert change.tasks.roots.all? { |card| card.milestone == change.milestone }
  end

  test "marks are recognised by number after the short name changes, and written anew" do
    change = import(LABELS).change
    @project.update!(short_name: "QA")

    again = import(change.tasks_text)

    assert_no_match(/goalner:GOAL-/, again.change.tasks_text)
    assert_equal 8, again.change.tasks_text.scan(/goalner:QA-\d+/).size
  end

  # Archive (task 3.3)

  test "a removed item is archived" do
    change = import(LABELS).change
    model = change.tasks.find_by!(title: "1.2 Add the model")

    import(change.tasks_text.lines.reject { |line| line.include?("1.2 Add the model") }.join)

    assert model.reload.archived?
  end

  test "a removed section is archived with its subtasks, including ones added in Goalner" do
    change = import(LABELS).change
    api = change.tasks.roots.find_by!(title: "add-labels: 2. API")
    extra = @project.tasks.create!(title: "Added by hand", parent: api, creator: users(:two))

    import(change.tasks_text.split("## 2. API").first)

    assert api.reload.archived?
    assert api.subtasks.none?
    assert extra.reload.archived?
    assert_equal 3, Task.archived.where(parent_id: api.id).count - 1
  end

  test "a mark of an archived task of the change is no mark: a new task is created and the mark replaced" do
    change = import(LABELS).change
    table = change.tasks.find_by!(title: "1.1 Add the table")
    table.archive!

    again = import(change.tasks_text).change

    fresh = again.tasks.kept.find_by!(title: "1.1 Add the table")
    assert_not_equal table, fresh
    assert_includes again.tasks_text, "1.1 Add the table <!-- goalner:#{fresh.key} -->"
    assert_not_includes again.tasks_text, "goalner:#{table.key} "
  end

  # Completion (task 3.4)

  test "a checked item is completed" do
    change = import(LABELS).change

    import(change.tasks_text.sub("- [ ] 1.2 Add the model", "- [x] 1.2 Add the model"))

    assert change.tasks.find_by!(title: "1.2 Add the model").done?
  end

  test "an item done in Goalner stays done and is checked in the returned text" do
    change = import(LABELS).change
    model = change.tasks.find_by!(title: "1.2 Add the model")
    model.update!(status: statuses(:goal_done))

    again = import(change.tasks_text).change

    assert model.reload.done?
    assert_includes again.tasks_text, "- [x] 1.2 Add the model <!-- goalner:#{model.key} -->"
  end

  test "an import never reopens" do
    change = import(LABELS.sub("- [ ] 1.2", "- [x] 1.2")).change
    model = change.tasks.find_by!(title: "1.2 Add the model")
    assert model.done?

    import(change.tasks_text.sub("- [x] 1.2", "- [ ] 1.2"))

    assert model.reload.done?
  end

  test "a card whose items are all done moves to the done column, and the milestone counts sections" do
    change = import(LABELS.gsub(/- \[ \] 1\./, "- [x] 1.")).change
    model, api = change.tasks.roots.order(:id).to_a

    assert model.done?
    assert_not api.done?
    assert_equal({ total: 2, done: 1 }, change.milestone.progress)
    assert_equal 0, api.subtasks.count { |subtask| subtask.done? }
  end

  test "a re-import without any mark is refused while the change has tasks" do
    import(LABELS)

    assert_no_difference counts do
      error = assert_raises(OpenspecChange::Import::KeysMissing) { import(LABELS) }
      assert_includes error.change.current_tasks_text, "goalner:GOAL-"
    end
  end

  # Carried-over cards (task 4.4; spec openspec-changes, "Carried-over cards")

  test "a carried-over copy belongs to no change and has no subtasks, and a re-import updates the original" do
    sprint = @project.sprints.create!(title: "Sprint 4", starts_on: Date.current, ends_on: 1.week.from_now)
    sprint.activate!
    change = import(LABELS).change
    card = change.tasks.roots.find_by!(title: "add-labels: 1. Model")
    next_sprint = @project.sprints.create!(title: "Sprint 5", starts_on: 1.week.from_now, ends_on: 2.weeks.from_now)

    sprint.archive!(carry_to: next_sprint)
    copy = next_sprint.tasks.find_by!(origin_task: card)
    import(change.tasks_text.sub("## 1. Model", "## 1. Model and table"))

    assert_nil copy.reload.openspec_change
    assert_empty copy.subtasks
    assert_equal "add-labels: 1. Model and table", card.reload.title
    assert_equal 3, card.subtasks.count
    assert_equal "add-labels: 1. Model", copy.title
  end

  # One transaction (task 3.5)

  test "a bad mark on the last line leaves everything as it was" do
    assert_no_difference counts do
      refusal { import(LABELS + "- [ ] 2.4 Bad <!-- goalner:GOAL-9999 -->\n") }
    end

    change = import(LABELS).change
    before = change.tasks.order(:id).map { |task| task.attributes.except("updated_at") }
    refusal { import(change.tasks_text.sub("1.1 Add the table", "1.1 Renamed") + "- [ ] 2.4 Bad <!-- goalner:GOAL-9999 -->\n") }
    assert_equal before, change.tasks.reload.order(:id).map { |task| task.attributes.except("updated_at") }
  end

  test "the marked text, importer and time are stored, and reading refreshes checkboxes" do
    change = import(LABELS).change
    import(change.tasks_text, user: users(:two))
    change.reload
    model = change.tasks.find_by!(title: "1.2 Add the model")

    assert_equal users(:two), change.imported_by
    model.update!(status: statuses(:goal_done))
    assert_includes change.current_tasks_text, "- [x] 1.2 Add the model"
    assert_includes change.tasks_text, "- [ ] 1.2 Add the model"
  end
end
