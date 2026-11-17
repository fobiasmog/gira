require "application_system_test_case"
require "support/drag_and_drop_helper"

# Spec board-drag-and-drop, "Move rows in the list layout", and the list
# layout's change tabs.
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

  test "the list layout shows a change's tab, keeps it when switching layouts, and has no move to the backlog" do
    change = @project.project_changes.create!(name: "add-labels")
    task("In the change", :goal_work).update!(change: change)
    task("In no change", :goal_todo)
    visit "/app/projects/#{@project.id}/list/changes/add-labels"

    assert_selector "[role=tab][aria-selected=true]", text: "add-labels"
    assert_equal [ "In the change" ], rows("Work")
    assert_empty rows("To Do")
    assert_no_button "Actions for GOAL-1"
    assert_no_text "Move to backlog"

    click_link "Board", href: "/app/projects/#{@project.id}/board/changes/add-labels"
    assert_current_path "/app/projects/#{@project.id}/board/changes/add-labels"
    within(".column", text: "Work", match: :first) { assert_text "In the change" }

    click_link "List", href: "/app/projects/#{@project.id}/list/changes/add-labels"
    find("[role=tab]", text: "Other tasks").click
    assert_current_path "/app/projects/#{@project.id}/list/other"
    assert_equal [ "In no change" ], rows("To Do")
  end

  test "the changes screen's move button shows its purpose and keeps its accessible name" do
    login = @project.project_changes.create!(name: "fix-login")
    @project.project_changes.create!(name: "export-csv")
    @project.tasks.create!(title: "Someday", creator: @user, change: login)
    visit "/app/projects/#{@project.id}/changes"

    button = find_button("Move GOAL-1")
    assert_equal "Move", button.text
    assert_equal "Move GOAL-1", button["aria-label"]

    button.click
    assert_button "export-csv"
    assert_button "Other tasks"
  end
end
