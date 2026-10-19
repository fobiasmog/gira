require "application_system_test_case"

# Spec web-client, "Screens" (board) and the board's column management.
class BoardTest < ApplicationSystemTestCase
  setup do
    @project = projects(:goal)
    @user = users(:one)
  end

  def task(title, status, **attributes)
    @project.tasks.create!(title: title, creator: @user, status: statuses(status), **attributes)
  end

  def visit_board
    sign_in @user.email_address, "correct horse battery"
    visit "/app/projects/#{@project.id}/board"
    assert_selector "h2", text: "To Do"
  end

  test "the board shows the columns in order with their cards' details" do
    label = @project.labels.create!(title: "Backend")
    first = task("Design the API", :goal_todo, label: label, assignee: users(:two), important: true, deadline: 1.day.from_now.change(hour: 12))
    task("Write the client", :goal_todo)
    task("Ship it", :goal_work)

    visit_board

    assert_equal [ "To Do", "Work", "Done" ], all(".column h2").map(&:text)
    within(".column", text: "To Do") do
      assert_text "2 tasks"
      card = find("article", text: "Design the API")
      within(card) do
        assert_text first.key
        assert_text "Backend"
        assert_selector ".visually-hidden", text: "Assigned to User Two", visible: :all
        assert_selector ".visually-hidden", text: "Important", visible: :all
        assert_text "tomorrow"
      end
    end
    within(".column", text: "Work") { assert_text "Ship it" }

    click_link "Design the API"
    assert_selector "h1", text: "Design the API"
    assert_current_path "/app/projects/#{@project.id}/tasks/#{first.key}"
  end

  test "add, rename and delete a column; the deleted column's tasks go to the backlog" do
    task("Orphan", :goal_work)
    visit_board

    click_button "Add column"
    fill_in "Column title", with: "Review"
    click_button "Create"
    assert_selector ".column h2", text: "Review"
    assert_equal [ "To Do", "Work", "Review", "Done" ], all(".column h2").map(&:text)

    click_button "Actions for column Review"
    click_button "Rename column"
    find_field("Column title").send_keys([ :control, "a" ], "QA", :enter)
    assert_selector ".column h2", text: "QA"

    click_button "Actions for column Work"
    click_button "Delete column"
    within("dialog[open]") { click_button "Delete" }
    assert_no_selector ".column h2", text: "Work"
    assert_no_text "Orphan"

    assert_equal [ "To Do", "QA", "Done" ], @project.statuses.reload.map(&:title)
    assert_nil Task.find_by!(title: "Orphan").status_id
  end

  test "add a task to a column" do
    visit_board

    click_button "Add task to To Do"
    fill_in "Task title", with: "Brand new task"
    find_field("Task title").send_keys(:enter)

    within(".column", text: "To Do") { assert_text "Brand new task" }
    assert_equal statuses(:goal_todo), Task.find_by!(title: "Brand new task").status
  end
end
