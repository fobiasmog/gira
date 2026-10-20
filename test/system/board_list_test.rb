require "application_system_test_case"
require "support/drag_and_drop_helper"

# Spec board-drag-and-drop, "Move rows in the list layout", and the backlog.
class BoardListTest < ApplicationSystemTestCase
  include DragAndDropHelper

  setup do
    @project = projects(:goal)
    @user = users(:one)
    sign_in @user.email_address, "correct horse battery"
  end

  def task(title, status)
    @project.tasks.create!(title: title, creator: @user, status: status && statuses(status))
  end

  def group(title)
    find(".board-list__group", text: title, match: :first) { |g| g.find("h2").text == title }
  end

  def rows(title)
    group(title).all("[data-drag-item=row] .task-row__title").map(&:text)
  end

  def row(title)
    find("[data-drag-item=row]", text: title)
  end

  test "the list layout groups tasks by column" do
    task("Plan", :goal_todo)
    task("Build", :goal_work)
    visit "/app/projects/#{@project.id}/list"

    assert_equal [ "To Do", "Work", "Done" ], all(".board-list__group h2").map(&:text)
    assert_equal [ "Plan" ], rows("To Do")
    assert_equal [ "Build" ], rows("Work")
    assert_selector "[aria-current=page]", text: "List"
  end

  test "row to another group: saved in the done column at the dropped position" do
    task("Finished earlier", :goal_done)
    task("Finished later", :goal_done)
    moved = task("Wrap up", :goal_todo)
    visit "/app/projects/#{@project.id}/list"

    drag_and_drop(row("Wrap up").find(".drag-handle", visible: :all), group("Done").find("ol"), before: row("Finished later"))

    within(group("Done")) { assert_text "Wrap up" }
    assert_equal [ "Finished earlier", "Wrap up", "Finished later" ], rows("Done")
    assert_empty rows("To Do")
    assert_equal [ statuses(:goal_done).id, 1 ], [ moved.reload.status_id, moved.position ]
    assert moved.completed_at, "a task moved to the done column is completed"
  end

  test "rows move by keyboard too" do
    task("One", :goal_todo)
    task("Two", :goal_todo)
    visit "/app/projects/#{@project.id}/list"

    link = row("Two").find(".task-row__title")
    execute_script("arguments[0].focus()", link)
    link.send_keys([ :alt, :arrow_right ])

    within(group("Work")) { assert_text "Two" }
    assert_equal "Two", evaluate_script("document.activeElement.textContent.trim()")
  end

  test "move to backlog during a sprint, then put the task back on the board" do
    sprint = @project.sprints.create!(title: "Sprint 1", starts_on: Date.current, ends_on: 13.days.from_now, active: true)
    task("Someday", :goal_work).update!(sprint: sprint)
    visit "/app/projects/#{@project.id}/list"

    click_button "Actions for GOAL-1"
    click_button "Move to backlog"
    assert_text "GOAL-1 moved to the backlog"
    assert_empty rows("Work")
    moved = Task.find_by!(title: "Someday")
    assert_equal [ nil, statuses(:goal_work) ], [ moved.sprint, moved.status ]

    within(".side-nav") { click_link "Backlog" }
    assert_selector "h1", text: "Backlog"
    within(".backlog > li", text: "Someday") { assert_text "Work" }

    click_button "Move GOAL-1"
    click_button "To Do"
    assert_text "GOAL-1 is now in To Do"
    assert_text "The backlog is empty."

    within(".side-nav") { click_link "Board" }
    within(".column", text: "To Do", match: :first) { assert_text "Someday" }
    assert_equal [ sprint, statuses(:goal_todo) ], [ moved.reload.sprint, moved.status ]
  end

  test "no active sprint: the board offers no move to the backlog" do
    task("Someday", :goal_todo)
    visit "/app/projects/#{@project.id}/list"

    assert_equal [ "Someday" ], rows("To Do")
    assert_no_button "Actions for GOAL-1"
    assert_no_button "Move to backlog"
  end

  test "a task created in the backlog during a sprint stays off the board" do
    @project.sprints.create!(title: "Sprint 1", starts_on: Date.current, ends_on: 13.days.from_now, active: true)
    visit "/app/projects/#{@project.id}/backlog"

    fill_in "New backlog task", with: "Idea"
    click_button "Create"

    within(".backlog") { assert_text "Idea" }
    idea = Task.find_by!(title: "Idea")
    assert_equal [ nil, statuses(:goal_todo) ], [ idea.sprint, idea.status ]
  end

  test "the backlog's move button shows its purpose and keeps its accessible name" do
    @project.sprints.create!(title: "Sprint 1", starts_on: Date.current, ends_on: 13.days.from_now, active: true)
    @project.tasks.create!(title: "Someday", creator: @user)
    visit "/app/projects/#{@project.id}/backlog"

    assert_selector "h1", text: "Backlog"
    assert_selector "h1 .badge", text: "1"
    button = find_button("Move GOAL-1")
    assert_equal "Move", button.text
    assert_equal "Move GOAL-1", button["aria-label"]

    button.click
    assert_button "Sprint 1"
    assert_button "To Do"
    assert_button "Done"
  end
end
