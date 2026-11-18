require "test_helper"

# Spec openspec-changes: "Import a change", "Cards and subtasks in their
# change", "Goalner keys in the tasks text", "Import again", "Limits of a
# change" and "Files of a change"; spec changes, "Change history";
# add-openspec-changes design.md, decisions 3 to 5;
# replace-sprints-with-changes design.md, decisions 3 and 4;
# add-change-conversation design.md, decisions 4 to 6.
class Change::ImportTest < ActiveSupport::TestCase
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
    Change::Import.new(project:, user:, name:, artifacts: artifacts || { "tasks" => text }).run!
  end

  def refusal(**options, &block)
    error = assert_raises(ActiveRecord::RecordInvalid, &block)
    error.record.errors
  end

  def counts = [ -> { Task.count }, -> { Change.count } ]

  def hand_made(title, change:, **attributes)
    @project.tasks.create!(title:, change:, creator: users(:two), **attributes)
  end

  def task(key) = @project.tasks.find_by_ref!(key)

  def keys_in(text) = text.scan(/goalner:(TEST|GOAL)-(\d+)/).map { |_, number| number.to_i }

  # First import

  test "a first import creates the open change, its cards and subtasks, all in the change" do
    result = import(LABELS)
    change = result.change

    assert result.created
    assert_equal "add-labels", change.name
    assert_not change.archived?
    assert_equal users(:one), change.imported_by
    assert_not_nil change.imported_at

    cards = change.tasks.roots.order(:position)
    assert_equal [ "add-labels: 1. Model", "add-labels: 2. API" ], cards.map(&:title)
    assert_equal [ [ "1.1 Add the table", "1.2 Add the model", "1.3 Add the validations" ],
                   [ "2.1 Add the routes", "2.2 Add the controller", "2.3 Add the docs" ] ], cards.map { |card| card.subtasks.map(&:title) }
    assert_equal 8, change.tasks.count
    assert change.tasks.all?(&:in_tasks_md)
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

  test "cards go into their change, whatever other changes the project holds" do
    export = @project.project_changes.create!(name: "export-csv")
    other = hand_made("Rate limiting", change: export, status: statuses(:goal_todo))

    change = import(LABELS).change

    assert_equal 2, change.tasks.roots.count
    assert_equal [ other ], export.tasks.to_a
    assert_equal [ 0, 1 ], change.tasks.roots.order(:position).map(&:position)
    assert_equal 0, other.reload.position
  end

  test "a change created by hand is imported into: 200, and its task added by hand stays as it is" do
    export = @project.project_changes.create!(name: "export-csv")
    by_hand = hand_made("Rate limiting", change: export, status: statuses(:goal_work))

    result = assert_no_difference(-> { Change.count }) { import(LABELS, name: "export-csv") }

    assert_not result.created
    assert_equal export, result.change
    assert_equal 9, export.tasks.count
    assert_equal [ "Rate limiting", statuses(:goal_work), export, false ], by_hand.reload.values_at(:title, :status, :change, :in_tasks_md)
    assert_not by_hand.archived?
  end

  test "the same name in two projects makes two changes" do
    import(LABELS)
    other = import("## 1. Side\n- [ ] 1.1 Item\n", project: projects(:side), user: users(:two)).change

    assert_equal projects(:side), other.project
    assert_equal 2, Change.where(name: "add-labels").count
    assert_equal 6, @project.project_changes.find_by!(name: "add-labels").tasks.where.not(parent_id: nil).count
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

  test "artifacts other than tasks, proposal, design and specs are refused" do
    errors = refusal { import(nil, artifacts: { "tasks" => LABELS, "notes" => "# Notes" }) }

    assert_equal [ "Notes is not an artifact Goalner imports" ], errors.full_messages_for(:notes)
    assert_equal 0, Change.count
  end

  test "a proposal, a design or a spec that is not a text is refused, naming the field or the key" do
    assert_no_difference [ *counts, -> { ChangeFile.count } ] do
      assert refusal { import(nil, artifacts: { "tasks" => LABELS, "proposal" => 3 }) }.include?(:proposal)
      assert refusal { import(nil, artifacts: { "tasks" => LABELS, "design" => [ "x" ] }) }.include?(:design)
      assert refusal { import(nil, artifacts: { "tasks" => LABELS, "specs" => "## export" }) }.include?(:specs)
      assert_equal [ "Specs export: must be a text" ], refusal { import(nil, artifacts: { "tasks" => LABELS, "specs" => { "export" => 1 } }) }.full_messages
    end
  end

  test "an invalid capability path is refused, naming the key, and nothing changes" do
    change = import(LABELS).change
    before = change.reload.attributes

    [ "../secrets", "Export", "identity//user-auth", "export/", "a--b", "" ].each do |key|
      errors = refusal { import(nil, artifacts: { "tasks" => change.tasks_text, "specs" => { "export" => "# ok", key => "# bad" } }) }
      assert_equal 1, errors[:specs].size, key
      assert errors[:specs].first.start_with?("#{key}: is not a capability path"), key
    end
    assert_equal before, change.reload.attributes
    assert_empty change.files
    assert_equal 1, change.events.count
  end

  test "a proposal, a design or a spec of 100,001 characters is refused" do
    long = "a" * 100_001

    assert_no_difference [ *counts, -> { ChangeFile.count } ] do
      assert_equal [ "Proposal is too long (maximum is 100000 characters)" ], refusal { import(nil, artifacts: { "tasks" => LABELS, "proposal" => long }) }.full_messages
      assert_equal [ "Design is too long (maximum is 100000 characters)" ], refusal { import(nil, artifacts: { "tasks" => LABELS, "design" => long }) }.full_messages
      assert_match(/export: is too long/, refusal { import(nil, artifacts: { "tasks" => LABELS, "specs" => { "export" => long } }) }.full_messages.join)
    end
    assert import(nil, artifacts: { "tasks" => LABELS, "proposal" => "a" * 100_000 })
  end

  test "more than 50 specs are refused" do
    specs = (1..51).to_h { |n| [ "cap-#{n}", "# #{n}" ] }

    assert_no_difference [ *counts, -> { ChangeFile.count } ] do
      assert_match(/51 specs/, refusal { import(nil, artifacts: { "tasks" => LABELS, "specs" => specs }) }.full_messages_for(:specs).join)
    end
    assert_equal 50, import(nil, artifacts: { "tasks" => LABELS, "specs" => specs.first(50).to_h }).change.files.count
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

  test "the text wins over a title edited in Goalner, and keeps the column, change and position" do
    change = import(LABELS).change
    card = change.tasks.roots.find_by!(title: "add-labels: 2. API")
    card.update!(title: "Renamed in Goalner", status: statuses(:goal_work))

    import(change.tasks_text)

    card.reload
    assert_equal "add-labels: 2. API", card.title
    assert_equal [ statuses(:goal_work), change, 0 ], [ card.status, card.change, card.position ]
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

  test "a card whose items are all done moves to the done column, and the change counts its cards" do
    change = import(LABELS.gsub(/- \[ \] 1\./, "- [x] 1.")).change
    model, api = change.tasks.roots.order(:id).to_a

    assert model.done?
    assert_not api.done?
    assert_equal({ by_status: { statuses(:goal_todo).id => 1, statuses(:goal_done).id => 1 }, total: 2 }, change.task_counts)
    assert_equal 0, api.subtasks.count { |subtask| subtask.done? }
  end

  test "a re-import without any mark is refused while the change has tasks.md cards" do
    import(LABELS)

    assert_no_difference counts do
      error = assert_raises(Change::Import::KeysMissing) { import(LABELS) }
      assert_includes error.change.current_tasks_text, "goalner:GOAL-"
    end
  end

  # Tasks added by hand (spec openspec-changes, "Adopting a task added by
  # hand" and "Task added by hand")

  test "a task added by hand is adopted by the mark that names it" do
    change = @project.project_changes.create!(name: "add-labels")
    by_hand = hand_made("Sketch", change:, status: statuses(:goal_work), description: "notes")

    again = import("## 1. Model <!-- goalner:#{by_hand.key} -->\n- [ ] 1.1 Add the table\n").change

    by_hand.reload
    assert_equal [ "add-labels: 1. Model", statuses(:goal_work), true ], by_hand.values_at(:title, :status, :in_tasks_md)
    assert_match(/\AOpenSpec change `add-labels`/, by_hand.description)
    assert_equal [ "1.1 Add the table" ], by_hand.subtasks.map(&:title)
    assert_includes again.tasks_text, "## 1. Model <!-- goalner:#{by_hand.key} -->"
  end

  test "a task added by hand to the change is not archived by a re-import that does not mention it" do
    change = import(LABELS).change
    card = hand_made("Fix flaky test", change:, status: statuses(:goal_todo))
    step = hand_made("Look at the logs", change:, parent: change.tasks.roots.first)

    import(change.tasks_text)
    import(change.reload.tasks_text.split("## 2. API").first)

    assert_not card.reload.archived?
    assert_equal "Fix flaky test", card.title
    assert_not step.reload.archived?
  end

  test "a change whose only tasks were added by hand takes a text without marks" do
    change = @project.project_changes.create!(name: "add-labels")
    hand_made("Fix flaky test", change:)

    assert_not import(LABELS).created
    assert_equal 9, change.tasks.count
  end

  # Archived changes (spec openspec-changes, "Import after archiving")

  test "importing an archived change's marked text is refused, naming the first marked line, and creates no change" do
    change = import(LABELS).change
    change.archive!

    assert_no_difference counts do
      errors = refusal { import(change.tasks_text) }
      assert_match(/\ATasks line 3: the mark names GOAL-\d+, which does not belong to this change\z/, errors.full_messages.first)
    end
  end

  test "a new change may take an archived change's name, and an import without marks fills it" do
    archived = import(LABELS).change
    archived.archive!

    fresh = import(LABELS)

    assert fresh.created
    assert_not_equal archived, fresh.change
    assert_equal 8, fresh.change.tasks.count
    assert_equal 8, archived.tasks.count
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

  # Files and phase (add-change-conversation, tasks 2.1 and 2.2)

  def artifacts(tasks = LABELS, **files) = { "tasks" => tasks, **files.transform_keys(&:to_s) }

  def paths(change) = change.files.in_order.pluck(:path)

  test "first import: the change is created in Proposed, with an import and no move in its history" do
    change = import(nil, artifacts: artifacts(proposal: "# Why")).change

    assert_equal "proposed", change.phase
    assert_equal [ [ "import", nil, %w[proposal.md tasks.md], users(:one) ] ], change.events.map { |e| [ e.kind, e.phase, e.paths, e.actor ] }
    assert_nil change.idea
  end

  test "change created by hand, moved to Exploring: the import moves it to Proposed and records the import, then the move" do
    export = @project.project_changes.create!(name: "export-csv", idea: "CSV")
    fish = create_agent(@project).user
    export.move_to!("exploring", by: fish)

    result = import(nil, name: "export-csv", user: fish, artifacts: artifacts(proposal: "# Why", specs: { "export" => "## ADDED" }))

    assert_not result.created
    assert_equal "proposed", export.reload.phase
    assert_equal [ [ "phase", "exploring", nil ], [ "import", nil, %w[proposal.md specs/export/spec.md tasks.md] ], [ "phase", "proposed", nil ] ],
      export.events.map { |e| [ e.kind, e.phase, e.paths ] }
    assert export.events.all? { |e| e.actor == fish }
    assert_equal "CSV", export.idea
  end

  test "an import into a change in Idea moves it to Proposed as well" do
    export = @project.project_changes.create!(name: "export-csv")

    import(LABELS, name: "export-csv")

    assert_equal "proposed", export.reload.phase
    assert_equal %w[import phase], export.events.map(&:kind)
  end

  test "import during implementation: the phase stays, and the new item becomes a subtask" do
    change = import(LABELS).change
    change.move_to!("implementing", by: users(:one))

    import(change.tasks_text + "- [ ] 2.4 Add the changelog\n")

    assert_equal "implementing", change.reload.phase
    assert change.tasks.exists?(title: "2.4 Add the changelog")
    assert_equal %w[import phase import], change.events.map(&:kind)
  end

  test "an import into a change in Proposed records the import only" do
    change = import(LABELS).change

    import(change.tasks_text, user: users(:two))

    assert_equal [ [ "import", users(:one) ], [ "import", users(:two) ] ], change.events.map { |e| [ e.kind, e.actor ] }
  end

  test "all the files: stored exactly as sent, in order, and listed in the import's history line" do
    proposal = "# Proposal\n\n## Why\n\nBecause.  \n"
    files = { proposal:, design: "# Design\n", specs: { "identity/user-auth" => "## MODIFIED\n", "export" => "## ADDED\n" } }

    change = import(nil, name: "export-csv", artifacts: artifacts(**files)).change

    assert_equal %w[proposal.md design.md specs/export/spec.md specs/identity/user-auth/spec.md], paths(change)
    assert_equal proposal, change.files.find_by!(path: "proposal.md").text
    assert_equal "## MODIFIED\n", change.files.find_by!(path: "specs/identity/user-auth/spec.md").text
    assert_equal %w[proposal.md design.md specs/export/spec.md specs/identity/user-auth/spec.md tasks.md], change.events.last.paths
  end

  test "a file no longer sent no longer belongs to the change, and a file sent again is replaced" do
    change = import(nil, name: "export-csv", artifacts: artifacts(proposal: "# One", design: "# D", specs: { "export" => "# E" })).change

    import(nil, name: "export-csv", artifacts: artifacts(change.tasks_text, proposal: "# Two", specs: { "export" => "# E" }))

    assert_equal %w[proposal.md specs/export/spec.md], paths(change)
    assert_equal "# Two", change.files.find_by!(path: "proposal.md").text
    assert_equal %w[proposal.md specs/export/spec.md tasks.md], change.events.last.paths

    import(nil, name: "export-csv", artifacts: artifacts(change.reload.tasks_text, proposal: nil))
    assert_empty paths(change)
    assert_equal %w[tasks.md], change.events.last.paths
  end

  test "all or nothing: a refused import leaves the files, the phase and the history as they were" do
    change = @project.project_changes.create!(name: "export-csv")
    change.move_to!("exploring", by: users(:one))
    import(nil, name: "export-csv", artifacts: artifacts(proposal: "# One", design: "# D"))
    change.update!(phase: "exploring")
    before = [ paths(change), change.files.pluck(:text), change.events.count, change.reload.phase ]

    assert_no_difference counts do
      refusal { import(nil, name: "export-csv", artifacts: artifacts(change.tasks_text + "- [ ] 2.4 Bad <!-- goalner:GOAL-9999 -->\n", proposal: "# Two")) }
    end
    assert_raises(Change::Import::KeysMissing) { import(nil, name: "export-csv", artifacts: artifacts(LABELS, proposal: "# Two")) }
    assert_equal before, [ paths(change), change.files.pluck(:text), change.events.count, change.reload.phase ]
  end
end
