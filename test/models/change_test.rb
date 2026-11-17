require "test_helper"

# Spec changes: "Changes in a project", "Archive a change", "Tasks in a
# change" and "Change lists and statistics"; spec openspec-changes, "Read a
# change".
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
end
