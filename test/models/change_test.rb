require "test_helper"

# Spec changes: "Changes in a project", "Archive a change", "Tasks in a
# change", "Change lists and statistics", "Idea of a change", "Phase of a
# change", "Change history" and "Waiting for people"; spec openspec-changes,
# "Read a change".
class ChangeTest < ActiveSupport::TestCase
  setup { @project = projects(:goal) }

  def create_change(name, project: @project) = project.project_changes.create!(name:)

  def create_task(title, change: nil, status: statuses(:goal_todo), **attributes)
    @project.tasks.create!(title:, change:, status:, creator: users(:one), **attributes)
  end

  # Changes in a project

  test "a change is named by groups of lowercase letters and digits joined by single hyphens" do
    %w[add-agents a fix-2fa v2 add-mcp-oauth].each do |name|
      assert @project.project_changes.new(name:).valid?, name
    end
    assert @project.project_changes.new(name: "a" * 100).valid?
  end

  test "other names are invalid" do
    [ "Add Agents", "Export CSV", "add_agents", "add--agents", "-add", "add-", "add agents", "", "a" * 101, "добавить" ].each do |name|
      change = @project.project_changes.new(name:)
      assert_not change.valid?, name
      assert change.errors.include?(:name), name
    end
  end

  test "several open changes, none of them active" do
    labels = create_change("add-labels")
    export = create_change("export-csv")

    assert_equal [ export, labels ], @project.project_changes.kept.newest_first.to_a
    assert_not Change.column_names.include?("active")
  end

  test "no two open changes of a project share a name" do
    create_change("add-labels")

    duplicate = @project.project_changes.new(name: "add-labels")
    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:name, :taken)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "a new change may take an archived change's name, and the archived one keeps its tasks" do
    archived = create_change("add-labels")
    task = create_task("Model", change: archived)
    archived.archive!

    fresh = create_change("add-labels")

    assert_empty fresh.tasks
    assert_equal [ task ], archived.tasks.to_a
    assert_equal [ fresh ], @project.project_changes.kept.to_a
  end

  test "the same name in two projects" do
    test_change = create_change("add-agents")
    other = create_change("add-agents", project: projects(:side))

    assert_equal projects(:side), other.project
    assert_equal "add-agents", test_change.reload.name
  end

  test "an id, or an open change's name, finds a change" do
    labels = create_change("add-labels")
    archived = create_change("export-csv").tap(&:archive!)

    assert_equal labels, @project.project_changes.find_by_ref!("add-labels")
    assert_equal labels, @project.project_changes.find_by_ref!(labels.id.to_s)
    assert_equal archived, @project.project_changes.find_by_ref!(archived.id)
    assert_raises(ActiveRecord::RecordNotFound) { @project.project_changes.find_by_ref!("export-csv") }
    assert_raises(ActiveRecord::RecordNotFound) { @project.project_changes.find_by_ref!("no-such-change") }
    assert_raises(ActiveRecord::RecordNotFound) { projects(:side).project_changes.find_by_ref!(labels.id) }
  end

  # Archive

  test "archiving keeps the tasks, and archiving twice keeps the first archive time" do
    change = create_change("add-labels")
    task = create_task("Model", change:)

    travel_to 1.day.ago do
      change.archive!
    end
    yesterday = change.reload.archived_at
    change.archive!

    assert_equal yesterday, change.reload.archived_at
    assert_equal [ change ], @project.project_changes.archived.to_a
    assert_equal change, task.reload.change
  end

  # Statistics

  test "task counts are of root, non-archived tasks, per column and in total" do
    change = create_change("add-labels")
    cards = [ create_task("A", change:), create_task("B", change:), create_task("C", change:, status: statuses(:goal_done)) ]
    3.times { |i| create_task("Step #{i}", change:, parent: cards.first) }
    create_task("Gone", change:).archive!
    create_task("Elsewhere")

    assert_equal({ by_status: { statuses(:goal_todo).id => 2, statuses(:goal_done).id => 1 }, total: 3 }, change.task_counts)
    assert_equal({ by_status: {}, total: 0 }, Change.task_counts_for([ create_change("empty") ]).values.first)
  end

  # Read a change

  test "a change never imported has no tasks text" do
    change = create_change("export-csv")

    assert_nil change.current_tasks_text
    assert_nil change.imported_by
    assert_nil change.imported_at
  end

  # Tasks in a change

  test "a change of another project or an unknown change is rejected" do
    task = create_task("T")

    assert_not task.update(change: create_change("add-labels", project: projects(:side)))
    assert task.errors.of_kind?(:change, :invalid)
    assert_not task.update(change_id: 0)
    assert_nil task.reload.change
  end

  test "no task is put into an archived change" do
    change = create_change("add-labels").tap(&:archive!)
    task = create_task("T")

    assert_not task.update(change:)
    assert task.errors.of_kind?(:change, :archived)
    assert_raises(ActiveRecord::RecordInvalid) { create_task("New", change:) }
    assert_nil task.reload.change
  end

  test "tasks already in a change stay editable after it is archived" do
    change = create_change("add-labels")
    task = create_task("T", change:)
    change.archive!

    assert task.reload.update(title: "Renamed")
  end

  test "moving a task to another change keeps its column, and its subtasks follow, archived ones too" do
    login = create_change("fix-login")
    export = create_change("export-csv")
    task = create_task("TEST-9", change: login, status: statuses(:goal_work))
    steps = 2.times.map { |i| create_task("Step #{i}", parent: task) }
    gone = create_task("Old step", parent: task).tap(&:archive!)

    Task.find(task.id).update!(change: export)

    assert_equal [ export, statuses(:goal_work) ], [ task.reload.change, task.status ]
    assert_equal [ export.id ] * 3, [ *steps, gone ].map { |step| step.reload.change_id }
    assert_empty login.tasks.kept
  end

  test "taking a task out of its change leaves it in no change, in its column" do
    login = create_change("fix-login")
    task = create_task("TEST-9", change: login, status: statuses(:goal_work))
    step = create_task("Step", parent: task)

    task.update!(change: nil)

    assert_equal [ nil, statuses(:goal_work) ], [ task.reload.change, task.status ]
    assert_nil step.reload.change
  end

  test "a subtask takes its card's change when created, and cannot be moved on its own" do
    change = create_change("add-labels")
    card = create_task("Card", change:)
    step = create_task("Step", parent: card)

    assert_equal change, step.change
    assert_not step.update(change: nil)
    assert step.errors.of_kind?(:change, :subtask)
  end

  test "a card of tasks.md stays in its change" do
    labels = create_change("add-labels")
    export = create_change("export-csv")
    card = create_task("add-labels: 1. Model", change: labels, in_tasks_md: true)

    assert_not card.update(change: export)
    assert card.errors.of_kind?(:change, :in_tasks_md)
    assert_not Task.find(card.id).update(change: nil)
    assert_equal labels, card.reload.change
  end

  test "moving between changes keeps positions contiguous in both lists" do
    labels = create_change("add-labels")
    export = create_change("export-csv")
    tasks = 3.times.map { |i| create_task("labels-#{i}", change: labels) }
    create_task("export-0", change: export)

    Task.find(tasks[0].id).update!(change: export)

    assert_equal [ [ "labels-1", 0 ], [ "labels-2", 1 ] ], labels.tasks.order(:position).pluck(:title, :position)
    assert_equal [ [ "export-0", 0 ], [ "labels-0", 1 ] ], export.tasks.order(:position).pluck(:title, :position)
  end

  # Idea of a change

  test "create with an idea: in Idea, with the idea exactly as written" do
    idea = "People want a project's tasks as CSV for weekly reports.\n\n- one\n- two\n"
    change = @project.project_changes.create!(name: "export-csv", idea:)

    assert_equal [ "idea", idea ], change.reload.values_at(:phase, :idea)
  end

  test "edit before exploring: the idea can be set, changed and cleared while in Idea" do
    change = create_change("export-csv")

    change.update!(idea: "First")
    assert_equal "First", change.reload.idea
    change.update!(idea: "Second")
    assert_equal "Second", change.reload.idea
    change.update!(idea: "")
    assert_nil change.reload.idea
  end

  test "fixed once exploring starts: changing the idea in any other phase is refused" do
    change = @project.project_changes.create!(name: "export-csv", idea: "First")
    change.move_to!("exploring", by: create_agent(@project).user)

    %w[exploring proposed implementing].each do |phase|
      change.update_column(:phase, phase)
      change.reload.idea = "Second"
      assert_not change.save, phase
      assert change.errors.of_kind?(:idea, :fixed), phase
      assert_equal "First", change.reload.idea
    end
  end

  test "the idea and the move out of Idea in one update: the idea is taken, then fixed" do
    change = create_change("export-csv")

    change.idea = "Written as exploring starts"
    change.move_to!("exploring", by: users(:one))

    assert_equal [ "exploring", "Written as exploring starts" ], change.reload.values_at(:phase, :idea)
  end

  test "the same idea again is no change, whatever the phase" do
    change = @project.project_changes.create!(name: "export-csv", idea: "First")
    change.update_column(:phase, "proposed")

    assert change.reload.update(idea: "First")
  end

  test "idea too long: refused, nothing created" do
    change = @project.project_changes.new(name: "export-csv", idea: "a" * 100_001)

    assert_not change.save
    assert change.errors.of_kind?(:idea, :too_long)
    assert @project.project_changes.new(name: "export-csv", idea: "a" * 100_000).valid?
  end

  # Phase of a change

  test "a new change is in Idea" do
    assert_equal "idea", create_change("export-csv").phase
  end

  test "agent moves the phase, and back to an earlier phase" do
    change = create_change("export-csv")
    fish = create_agent(@project).user

    change.move_to!("exploring", by: fish)
    assert_equal "exploring", change.reload.phase

    change.move_to!("proposed", by: fish)
    change.move_to!("exploring", by: users(:one))
    assert_equal "exploring", change.reload.phase
  end

  test "Done is reported while every card of a change in Implementing is in the done column, and not otherwise" do
    change = create_change("add-labels")
    cards = 4.times.map { |i| create_task("Card #{i}", change:, status: statuses(:goal_done)) }
    cards.first.update!(status: statuses(:goal_work))
    change.move_to!("implementing", by: users(:one))

    assert_equal "implementing", change.phase_reported
    cards.first.update!(status: statuses(:goal_done))
    assert_equal "done", change.phase_reported
    assert_equal "implementing", change.reload.phase

    cards.last.update!(status: statuses(:goal_todo))
    assert_equal "implementing", change.phase_reported
  end

  test "Done ignores archived cards and subtasks, and needs the change to be in Implementing" do
    change = create_change("add-labels")
    card = create_task("Card", change:, status: statuses(:goal_done))
    create_task("Open step", parent: card, status: statuses(:goal_todo))
    create_task("Gone", change:, status: statuses(:goal_todo)).archive!

    assert_equal "idea", change.phase_reported
    change.update!(phase: "proposed")
    assert_equal "proposed", change.phase_reported
    change.update!(phase: "implementing")
    assert_equal "done", change.phase_reported
  end

  test "implementing without cards is reported as Implementing" do
    change = create_change("fix-login")
    change.move_to!("implementing", by: users(:one))

    assert_equal "implementing", change.phase_reported
  end

  test "Done, or an unknown phase, cannot be chosen" do
    change = create_change("export-csv")

    [ "done", "review", "", nil ].each do |phase|
      error = assert_raises(ActiveRecord::RecordInvalid, phase.inspect) { change.move_to!(phase, by: users(:one)) }
      assert error.record.errors.include?(:phase), phase.inspect
      assert_equal "idea", change.reload.phase
    end
    assert_empty change.events
    assert_raises(ActiveRecord::StatementInvalid) { change.update_column(:phase, "done") }
  end

  test "an archived change keeps its phase and cannot be moved or edited" do
    change = @project.project_changes.create!(name: "fix-login", idea: "Fix it")
    change.move_to!("proposed", by: users(:one))
    change.archive!

    assert_raises(ActiveRecord::RecordInvalid) { change.reload.move_to!("exploring", by: users(:one)) }
    assert_equal "proposed", change.reload.phase
    assert_not change.update(idea: "Other")
    assert change.errors.of_kind?(:base, :archived)
    assert_equal [ "proposed" ], change.events.map(&:phase)
  end

  # Change history

  test "phase moves are recorded with who made them and when, oldest first" do
    change = create_change("export-csv")
    fish = create_agent(@project).user

    travel_to(1.hour.ago) { change.move_to!("exploring", by: fish) }
    change.move_to!("implementing", by: users(:one))

    events = change.reload.events
    assert_equal [ [ "phase", "exploring", fish ], [ "phase", "implementing", users(:one) ] ], events.map { |event| [ event.kind, event.phase, event.actor ] }
    assert_operator events.first.created_at, :<, events.last.created_at
  end

  test "moving to the same phase records nothing, and Done is never recorded" do
    change = create_change("export-csv")
    change.move_to!("proposed", by: users(:one))

    assert_no_difference(-> { ChangeEvent.count }) { change.move_to!("proposed", by: users(:two)) }

    change.move_to!("implementing", by: users(:one))
    create_task("Card", change:, status: statuses(:goal_done))
    assert_equal "done", change.phase_reported
    assert_equal %w[proposed implementing], change.events.reload.map(&:phase)
  end

  # Waiting for people

  test "an open change whose newest comment is an agent's is waiting, until a person answers" do
    export = create_change("export-csv")
    login = create_change("fix-login")
    fish = create_agent(@project).user

    assert_not export.waiting_for_people?
    export.comments.create!(author: users(:one), body: "Start please")
    export.comments.create!(author: fish, body: "Should archived tasks go into the file?")
    assert export.waiting_for_people?
    assert_equal Set[export.id], Change.waiting_for_people([ export, login ])

    export.comments.create!(author: users(:one), body: "No.")
    assert_not export.waiting_for_people?
  end

  test "the newest comment is the newest kept one, by time and then id" do
    change = create_change("export-csv")
    fish = create_agent(@project).user
    now = Time.current
    asked = change.comments.create!(author: fish, body: "Question", created_at: now)
    answer = change.comments.create!(author: users(:one), body: "Answer", created_at: now)

    assert_not change.waiting_for_people?
    answer.soft_delete!
    assert change.waiting_for_people?
    asked.soft_delete!
    assert_not change.waiting_for_people?
  end

  test "no thread, a task comment by an agent, or an archived change: not waiting" do
    change = create_change("fix-login")
    fish = create_agent(@project).user
    create_task("T", change:).comments.create!(author: fish, body: "On a task")

    assert_not change.waiting_for_people?

    change.comments.create!(author: fish, body: "Question")
    change.archive!
    assert_not change.reload.waiting_for_people?
    assert_empty Change.waiting_for_people([])
  end

  test "waiting for people for many changes takes one query" do
    changes = 3.times.map { |i| create_change("change-#{i}") }
    fish = create_agent(@project).user
    changes.each { |change| change.comments.create!(author: fish, body: "?") }

    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      assert_equal changes.map(&:id).to_set, Change.waiting_for_people(changes)
    end
    assert_equal 1, queries.size
  end

  # Base branch of a change (spec changes; add-runners-and-workspaces
  # design.md, decision 8)

  test "created by a member: the base branch is main, and it cannot be changed" do
    change = projects(:goal).project_changes.create!(name: "export-csv")

    assert_equal "main", change.base_branch
    assert_raises(ActiveRecord::ActiveRecordError) { change.update!(base_branch: "release/2.0") }
    assert_equal "main", change.reload.base_branch
  end

  test "created by an import: the base branch is main" do
    result = Change::Import.new(project: projects(:goal), user: users(:one), name: "add-tags", artifacts: { "tasks" => "## 1. Tags\n\n- [ ] 1.1 Add tags\n" }).run!

    assert_equal "main", result.change.reload.base_branch
  end
end
