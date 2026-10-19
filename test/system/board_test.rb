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
      assert_selector ".column__count", text: "2"
      assert_selector ".column__count .visually-hidden", text: "2 tasks", visible: :all
      card = find("article", text: "Design the API")
      within(card) do
        assert_text first.key
        assert_selector ".chip[data-tone]", text: "Backend"
        assert_selector ".visually-hidden", text: "Assigned to User Two", visible: :all
        assert_text "Important"
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

  test "an overdue deadline is highlighted and named" do
    task("Late task", :goal_todo, deadline: 1.day.ago.change(hour: 12))
    visit_board

    within("article", text: "Late task") { assert_selector "time.card__deadline--overdue", text: "yesterday" }
  end

  # Spec web-client, "Board sprint summary".
  test "the board shows the active sprint's progress" do
    sprint = @project.sprints.create!(title: "Sprint 14", starts_on: 6.days.ago.to_date, ends_on: 7.days.from_now.to_date)
    sprint.activate!
    9.times { |i| task("Open #{i}", i.even? ? :goal_todo : :goal_work, sprint: sprint) }
    3.times { |i| task("Finished #{i}", :goal_done, sprint: sprint) }
    task("Not in the sprint", :goal_todo)
    visit_board

    within("section[aria-label='Active sprint']") do
      assert_link "Sprint 14", href: "/app/projects/#{@project.id}/sprints"
      assert_selector ".sprint-summary__dates", text: /\b#{sprint.starts_on.day}\b.*\b#{sprint.ends_on.day}\b/
      assert_text "3 of 12 done"
      assert_selector "[role=progressbar][aria-valuenow='3'][aria-valuemax='12']"
      assert_text "7 days left"
    end
    assert_no_text "Not in the sprint"

    click_link "Sprint 14"
    assert_current_path "/app/projects/#{@project.id}/sprints"
  end

  test "the sprint summary in Russian" do
    @user.update!(lang: "ru")
    sprint = @project.sprints.create!(title: "Спринт 3", starts_on: 4.days.ago.to_date, ends_on: 3.days.from_now.to_date)
    sprint.activate!
    visit_board

    within("section[aria-label='Активный спринт']") do
      assert_text "Готово 0 из 0"
      assert_text "осталось 3 дня"
    end
  end

  test "a board without an active sprint shows no sprint summary" do
    task("Plain task", :goal_todo)
    visit_board

    assert_text "Plain task"
    assert_no_selector "section[aria-label='Active sprint']"
    assert_equal [ "To Do", "Work", "Done" ], all(".column h2").map(&:text)
  end

  # Spec web-client, "New task from the board header".
  test "add a task from the board header" do
    visit_board

    click_button "New task"
    assert_equal "Task title", evaluate_script("document.activeElement.getAttribute('aria-label')")
    assert_equal "To Do", evaluate_script("document.activeElement.closest('.column').querySelector('h2').textContent")
    find_field("Task title").send_keys("From the header", :enter)

    within(".column", text: "To Do") { assert_text "From the header" }
    assert_equal statuses(:goal_todo), Task.find_by!(title: "From the header").status
  end

  test "Escape closes the field opened from the header without creating a task" do
    visit_board

    click_button "New task"
    assert_field "Task title"
    find_field("Task title").send_keys(:escape)

    assert_no_field "Task title"
    assert_equal 0, @project.tasks.count
  end

  test "the header offers no new task in the list layout or without columns" do
    sign_in @user.email_address, "correct horse battery"
    visit "/app/projects/#{@project.id}/list"
    assert_selector "h2", text: "To Do"
    assert_no_button "New task"

    @project.statuses.destroy_all
    visit "/app/projects/#{@project.id}/board"
    assert_button "Add column"
    assert_no_button "New task"
  end
end
