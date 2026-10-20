require "application_system_test_case"

# Spec web-client, "Backlog screen".
class BacklogTest < ApplicationSystemTestCase
  setup do
    @project = projects(:goal)
    @user = users(:one)
    sign_in @user.email_address, "correct horse battery"
  end

  def sprint(title, active: false)
    @project.sprints.create!(title: title, starts_on: Date.current, ends_on: 13.days.from_now, active: active)
  end

  def task(title, status: :goal_todo, **attributes)
    @project.tasks.create!(title: title, creator: @user, status: statuses(status), **attributes)
  end

  def visit_backlog
    visit "/app/projects/#{@project.id}/backlog"
    assert_selector "h1", text: "Backlog"
  end

  def backlog_row(title)
    find(".backlog > li", text: title)
  end

  test "add a backlog task during a sprint: on the first column, not on the board" do
    sprint("Sprint 1", active: true)
    visit_backlog

    fill_in "New backlog task", with: "Dark mode"
    click_button "Create"

    within(backlog_row("Dark mode")) { assert_text "To Do" }
    task = Task.find_by!(title: "Dark mode")
    assert_equal [ statuses(:goal_todo), nil ], [ task.status, task.sprint ]

    within(".side-nav") { click_link "Board" }
    assert_selector ".column h2", text: "To Do"
    assert_no_text "Dark mode"
  end

  test "move a task into a planned sprint" do
    sprint("Sprint 1", active: true)
    planned = sprint("Sprint 3")
    task("TEST-1", status: :goal_work)
    visit_backlog
    within(backlog_row("TEST-1")) { assert_text "Work" }

    click_button "Move GOAL-1"
    click_button "Sprint 3"

    assert_text "GOAL-1 moved to Sprint 3"
    assert_text "The backlog is empty."
    assert_equal planned, Task.find_by!(title: "TEST-1").sprint

    within(".side-nav") { click_link "Sprints" }
    within(find(".sprint", text: "Sprint 3")) { assert_text "TEST-1" }
  end

  test "put a task on the board: it joins the active sprint at the end of the column" do
    active = sprint("Sprint 1", active: true)
    task("Already working", status: :goal_work, sprint: active)
    task("TEST-1")
    visit_backlog

    click_button "Move GOAL-2"
    click_button "Work"

    assert_text "GOAL-2 is now in Work"
    assert_text "The backlog is empty."
    moved = Task.find_by!(title: "TEST-1")
    assert_equal [ active, statuses(:goal_work), 1 ], [ moved.sprint, moved.status, moved.position ]

    within(".side-nav") { click_link "Board" }
    work = find(".column", text: "Work", match: :first) { |column| column.find("h2").text == "Work" }
    within(work) { assert_text "TEST-1" }
    assert_equal [ "Already working", "TEST-1" ], work.all(".card__title").map(&:text)
  end

  test "no active sprint: the move menu lists the open sprints and no board columns" do
    sprint("Sprint 3")
    task("TEST-1")
    visit_backlog

    click_button "Move GOAL-1"

    assert_button "Sprint 3"
    assert_no_text "On the board"
    assert_no_button "To Do"
    assert_no_button "Work"
  end

  test "done tasks outside sprints: a collapsed group below the list" do
    sprint("Sprint 1", active: true)
    task("Still open")
    task("Shipped A", status: :goal_done)
    task("Shipped B", status: :goal_done)
    visit_backlog

    within(".backlog") { assert_text "Still open" }
    assert_no_selector ".backlog", text: "Shipped"
    assert_selector "details:not([open]) summary", text: "Done (2)"
    assert_no_text "Shipped A"

    find("summary", text: "Done (2)").click
    assert_text "Shipped A"
    assert_text "Shipped B"
  end
end
