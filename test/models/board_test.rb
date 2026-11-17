require "test_helper"

class BoardTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(title: "Board", short_name: "BRD", owner: users(:one))
    @board = Board.new(@project)
    @todo, @work, @done = @project.statuses.to_a
  end

  def titles = @project.statuses.reload.map(&:title)
  def done_title = @project.statuses.reload.find(&:done).title

  def create_task(title, status: @todo, **attributes)
    @project.tasks.create!(title: title, creator: users(:one), status: status, **attributes)
  end

  def column(status, change: nil)
    @project.tasks.kept.roots.where(status: status, change: change).order(:position).pluck(:title, :position)
  end

  test "new project board" do
    assert_equal [ "To Do", "Work", "Done" ], titles
    assert_equal "Done", done_title
  end

  test "column added before the done column" do
    @board.add_column(title: "Review")

    assert_equal [ "To Do", "Work", "Review", "Done" ], titles
    assert_equal [ 0, 1, 2, 3 ], @project.statuses.reload.map(&:position)
    assert_equal "Done", done_title
  end

  test "reordering: the column that ends up last becomes the done column" do
    @board.move_column(@done, position: 0)

    assert_equal [ "Done", "To Do", "Work" ], titles
    assert_equal "Work", done_title
    assert_equal 1, @project.statuses.where(done: true).count
  end

  test "moving a column to the end makes it the done column" do
    @board.move_column(@todo, position: 99)

    assert_equal [ "Work", "Done", "To Do" ], titles
    assert_equal "To Do", done_title
  end

  test "rename a column" do
    @board.rename_column(@work, title: "Doing")

    assert_equal [ "To Do", "Doing", "Done" ], titles
  end

  test "column title length" do
    assert_raises(ActiveRecord::RecordInvalid) { @board.add_column(title: "a" * 51) }
    assert_raises(ActiveRecord::RecordInvalid) { @board.add_column(title: "") }
  end

  test "delete a column with tasks: they go to the end of the first column intact, in their changes" do
    change = @project.project_changes.create!(name: "add-labels")
    create_task("waiting")
    create_task("change waiting", change: change)
    tasks = 2.times.map { |i| create_task("T#{i}", status: @work, description: "notes #{i}", important: true) }
    in_change = create_task("T2", status: @work, description: "notes 2", important: true, change: change)

    @board.delete_column(@work)

    assert_equal [ "To Do", "Done" ], titles
    tasks.each(&:reload)
    in_change.reload
    assert [ *tasks, in_change ].all? { |task| task.status == @todo && task.important && task.completed_at.nil? }
    assert_equal [ "notes 0", "notes 1", "notes 2" ], [ *tasks, in_change ].map(&:description)
    assert_equal change, in_change.change
    assert_equal [ [ "waiting", 0 ], [ "T0", 1 ], [ "T1", 2 ] ], column(@todo)
    assert_equal [ [ "change waiting", 0 ], [ "T2", 1 ] ], column(@todo, change: change)
  end

  test "delete the first column: its tasks go to the end of the next one" do
    create_task("working", status: @work)
    2.times { |i| create_task("T#{i}") }

    @board.delete_column(@todo)

    assert_equal [ "Work", "Done" ], titles
    assert_equal [ [ "working", 0 ], [ "T0", 1 ], [ "T1", 2 ] ], column(@work)
  end

  test "only the done column remains: the moved tasks are completed at the time of the deletion" do
    @board.delete_column(@work)
    tasks = 2.times.map { |i| create_task("T#{i}") }

    freeze_time do
      @board.delete_column(@todo)

      assert_equal [ "Done" ], titles
      assert tasks.map(&:reload).all? { |task| task.status == @done && task.completed_at == Time.current }
    end
  end

  test "archived tasks of a deleted column move to the first column too" do
    task = create_task("old", status: @work)
    task.archive!

    @board.delete_column(@work)

    assert_equal [ @todo.id, nil ], [ task.reload.status_id, task.position ]
  end

  test "deleting the done column makes the new last column the done column" do
    @board.delete_column(@done)

    assert_equal "Work", done_title
  end

  test "delete the only column" do
    @board.delete_column(@work)
    @board.delete_column(@done)

    assert_raises(Board::Error) { @board.delete_column(@todo) }
    assert_equal [ "To Do" ], titles
  end

  test "move between columns: both columns stay contiguous" do
    todo = 4.times.map { |i| create_task("todo#{i}") }
    2.times { |i| create_task("work#{i}", status: @work) }

    @board.place(todo[2], status_id: @work.id, position: 0)

    assert_equal [ [ "todo2", 0 ], [ "work0", 1 ], [ "work1", 2 ] ], column(@work)
    assert_equal [ [ "todo0", 0 ], [ "todo1", 1 ], [ "todo3", 2 ] ], column(@todo)
  end

  test "move within a column" do
    tasks = 3.times.map { |i| create_task("t#{i}") }

    @board.place(tasks[0], status_id: @todo.id, position: 2)

    assert_equal [ [ "t1", 0 ], [ "t2", 1 ], [ "t0", 2 ] ], column(@todo)
  end

  test "move into done records the completion time; moving out clears it" do
    task = create_task("t")

    freeze_time do
      @board.place(task, status_id: @done.id, position: 0)
      assert_equal Time.current, task.reload.completed_at
    end

    @board.place(task, status_id: @work.id, position: 0)
    assert_nil task.reload.completed_at
  end

  test "placement without a column is rejected and the task stays" do
    create_task("first")
    task = create_task("t")

    assert_raises(Board::Error) { @board.place(task, status_id: nil, position: 0) }
    assert_equal [ @todo.id, 1 ], [ task.reload.status_id, task.position ]
  end

  test "placement within a change orders only that change's tasks" do
    change = @project.project_changes.create!(name: "add-labels")
    other = 2.times.map { |i| create_task("other#{i}", status: @work) }
    tasks = 3.times.map { |i| create_task("change#{i}", change: change) }

    @board.place(tasks[2], status_id: @work.id, position: 0)

    assert_equal [ @work, change ], [ tasks[2].reload.status, tasks[2].change ]
    assert_equal [ [ "change2", 0 ] ], column(@work, change: change)
    assert_equal [ [ "change0", 0 ], [ "change1", 1 ] ], column(@todo, change: change)
    assert_equal [ [ "other0", 0 ], [ "other1", 1 ] ], column(@work)
    assert_equal [ 0, 1 ], other.map { |task| task.reload.position }
  end

  test "changing the change keeps the column; both lists stay contiguous" do
    c1 = @project.project_changes.create!(name: "c1")
    c2 = @project.project_changes.create!(name: "c2")
    tasks = 3.times.map { |i| create_task("c1-#{i}", status: @work, change: c1) }
    create_task("c2-0", status: @work, change: c2)

    # Freshly loaded each time, as the change endpoint does.
    Task.find(tasks[0].id).update!(change: c2)
    Task.find(tasks[1].id).update!(change: nil)

    assert_equal [ [ "c1-2", 0 ] ], column(@work, change: c1)
    assert_equal [ [ "c2-0", 0 ], [ "c1-0", 1 ] ], column(@work, change: c2)
    assert_equal [ [ "c1-1", 0 ] ], column(@work)
  end

  test "column from another project is rejected and the task stays" do
    task = create_task("t")

    assert_raises(Board::Error) { @board.place(task, status_id: statuses(:side_todo).id, position: 0) }
    assert_equal @todo.id, task.reload.status_id
  end

  test "an unknown column id is rejected" do
    task = create_task("t")

    assert_raises(Board::Error) { @board.place(task, status_id: 0, position: 0) }
    assert_equal @todo.id, task.reload.status_id
  end

  test "subtasks are not placed on the board" do
    parent = create_task("parent")
    subtask = create_task("sub", parent: parent)

    assert_raises(Board::Error) { @board.place(subtask, status_id: @work.id, position: 0) }
  end
end
