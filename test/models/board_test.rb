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

  test "delete a column with tasks: they go to the end of the first column intact, in their sprints" do
    sprint = @project.sprints.create!(title: "S1", starts_on: Date.current, ends_on: 1.week.from_now, active: true)
    create_task("waiting")
    create_task("sprint waiting", sprint: sprint)
    tasks = 2.times.map { |i| create_task("T#{i}", status: @work, description: "notes #{i}", important: true) }
    in_sprint = create_task("T2", status: @work, description: "notes 2", important: true, sprint: sprint)

    @board.delete_column(@work)

    assert_equal [ "To Do", "Done" ], titles
    tasks.each(&:reload)
    in_sprint.reload
    assert [ *tasks, in_sprint ].all? { |task| task.status == @todo && task.important && task.completed_at.nil? }
    assert_equal [ "notes 0", "notes 1", "notes 2" ], [ *tasks, in_sprint ].map(&:description)
    assert_equal sprint, in_sprint.sprint
    assert_equal [ [ "waiting", 0 ], [ "T0", 1 ], [ "T1", 2 ] ], column(@todo)
    assert_equal [ [ "sprint waiting", 0 ], [ "T2", 1 ] ], column(@todo, sprint: sprint)
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

  test "placement with a sprint change: both lists stay contiguous" do
    sprint = @project.sprints.create!(title: "S1", starts_on: Date.current, ends_on: 1.week.from_now, active: true)
    backlog = 3.times.map { |i| create_task("backlog#{i}") }
    2.times { |i| create_task("sprint#{i}", status: @work, sprint: sprint) }

    @board.place(backlog[1], status_id: @work.id, position: 0, sprint_id: sprint.id)

    assert_equal sprint, backlog[1].reload.sprint
    assert_equal [ [ "backlog1", 0 ], [ "sprint0", 1 ], [ "sprint1", 2 ] ], column(@work, sprint: sprint)
    assert_equal [ [ "backlog0", 0 ], [ "backlog2", 1 ] ], column(@todo)
  end

  test "changing the sprint keeps the column; both lists stay contiguous" do
    s1 = @project.sprints.create!(title: "S1", starts_on: Date.current, ends_on: 1.week.from_now)
    s2 = @project.sprints.create!(title: "S2", starts_on: Date.current, ends_on: 1.week.from_now)
    tasks = 3.times.map { |i| create_task("s1-#{i}", status: @work, sprint: s1) }
    create_task("s2-0", status: @work, sprint: s2)

    # Freshly loaded each time, as the sprint endpoint does.
    Task.find(tasks[0].id).update!(sprint: s2)
    Task.find(tasks[1].id).update!(sprint: nil)

    assert_equal [ [ "s1-2", 0 ] ], column(@work, sprint: s1)
    assert_equal [ [ "s2-0", 0 ], [ "s1-0", 1 ] ], column(@work, sprint: s2)
    assert_equal [ [ "s1-1", 0 ] ], column(@work)
  end

  test "placement without sprint_id keeps the sprint" do
    sprint = @project.sprints.create!(title: "S1", starts_on: Date.current, ends_on: 1.week.from_now)
    task = create_task("t", sprint: sprint)

    @board.place(task, status_id: @work.id, position: 0)

    assert_equal [ @work, sprint ], [ task.reload.status, task.sprint ]
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
