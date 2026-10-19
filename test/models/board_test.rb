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

  def column(status, sprint: nil)
    @project.tasks.kept.roots.where(status: status, sprint: sprint).order(:position).pluck(:title, :position)
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

  test "delete a column with tasks: they go to the backlog intact" do
    tasks = 3.times.map { |i| create_task("T#{i}", status: @work, description: "notes #{i}", important: true) }

    @board.delete_column(@work)

    assert_equal [ "To Do", "Done" ], titles
    tasks.each(&:reload)
    assert tasks.all? { |task| task.status_id.nil? && task.important }
    assert_equal [ "notes 0", "notes 1", "notes 2" ], tasks.map(&:description)
    assert_equal [ [ "T0", 0 ], [ "T1", 1 ], [ "T2", 2 ] ], column(nil)
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

  test "send to backlog" do
    task = create_task("t")
    create_task("other")

    @board.place(task, status_id: nil, position: 0)

    assert_nil task.reload.status_id
    assert_equal [ [ "other", 0 ] ], column(@todo)
    assert_equal [ [ "t", 0 ] ], column(nil)
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
