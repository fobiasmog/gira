require "application_system_test_case"

# Spec web-client: sprints and milestones screens.
class SprintsMilestonesTest < ApplicationSystemTestCase
  setup do
    @project = projects(:goal)
    @user = users(:one)
    sign_in @user.email_address, "correct horse battery"
  end

  def set_date(label, value)
    execute_script("arguments[0].value = arguments[1]; arguments[0].dispatchEvent(new Event('input', { bubbles: true }))", find_field(label), value)
  end

  def sprint_card(title)
    find(".sprint", text: title)
  end

  test "close the new sprint dialog with Escape: focus returns to the button" do
    visit "/app/projects/#{@project.id}/sprints"

    click_button "New sprint"
    assert_selector "dialog[open]", text: "Sprint name"
    find_field("Sprint name").send_keys(:escape)

    assert_no_selector "dialog[open]"
    assert_equal "New sprint", evaluate_script("document.activeElement.textContent.trim()")
  end

  test "create and activate a sprint; the board then shows its tasks" do
    visit "/app/projects/#{@project.id}/sprints"
    assert_text "There are no sprints yet."

    click_button "New sprint"
    within("dialog[open]") do
      fill_in "Sprint name", with: "Sprint 1"
      set_date "Starts on", Date.current.iso8601
      set_date "Ends on", 13.days.from_now.to_date.iso8601
      assert_checked_field "Make it the active sprint"
      click_button "Create sprint"
    end

    assert_text "Sprint “Sprint 1” created"
    within(sprint_card("Sprint 1")) { assert_text "Active" }
    sprint = @project.sprints.find_by!(title: "Sprint 1")
    assert sprint.active

    @project.tasks.create!(title: "In the sprint", creator: @user, status: statuses(:goal_todo), sprint: sprint)
    @project.tasks.create!(title: "Outside the sprint", creator: @user, status: statuses(:goal_todo))
    within(".side-nav") { click_link "Board" }
    within("section[aria-label='Active sprint']") { assert_link "Sprint 1" }
    assert_text "In the sprint"
    assert_no_text "Outside the sprint"
  end

  test "validation errors from the server are shown in the dialog" do
    visit "/app/projects/#{@project.id}/sprints"

    click_button "New sprint"
    within("dialog[open]") do
      fill_in "Sprint name", with: "Backwards"
      set_date "Starts on", Date.current.iso8601
      set_date "Ends on", 3.days.ago.to_date.iso8601
      click_button "Create sprint"
      assert_invalid_field "Ends on"
    end
    assert_nil @project.sprints.find_by(title: "Backwards")
  end

  test "activate another sprint, see per-column counts and archive with carry-over" do
    first = @project.sprints.create!(title: "First", starts_on: Date.current, ends_on: 7.days.from_now)
    first.activate!
    second = @project.sprints.create!(title: "Second", starts_on: 8.days.from_now, ends_on: 15.days.from_now)
    @project.tasks.create!(title: "Unfinished", creator: @user, status: statuses(:goal_work), sprint: first)
    @project.tasks.create!(title: "Finished", creator: @user, status: statuses(:goal_done), sprint: first)
    visit "/app/projects/#{@project.id}/sprints"

    within(sprint_card("First")) do
      assert_text "2 tasks in total"
      assert_text "Work 1"
      assert_text "Done 1"
    end

    within(sprint_card("Second")) { click_button "Activate" }
    assert_text "“Second” is now the active sprint"
    within(sprint_card("Second")) { assert_text "Active" }
    assert second.reload.active

    within(sprint_card("First")) { click_button "Archive" }
    within("dialog[open]") do
      choose "Second"
      click_button "Archive"
    end
    assert_text "“First” was archived"
    assert_no_selector ".sprint", text: "First"
    assert_text "Archived sprints (1)"
    assert first.reload.archived_at
    assert_includes second.tasks.kept.map(&:title), "Unfinished"
  end

  # Sprint planning

  def create_sprint(title, active: false)
    @project.sprints.create!(title: title, starts_on: Date.current, ends_on: 13.days.from_now, active: active)
  end

  def sprint_toggle(title)
    find("button[aria-controls]", text: title, exact_text: true)
  end

  def assert_expanded(title, expanded)
    assert_selector "button[aria-controls][aria-expanded=#{expanded}]", text: title, exact_text: true
  end

  test "plan a task: listed under the sprint, neither on the board nor in the backlog" do
    create_sprint("Sprint 1", active: true)
    planned = create_sprint("Sprint 3")
    visit "/app/projects/#{@project.id}/sprints"

    assert_expanded "Sprint 3", true
    within(sprint_card("Sprint 3")) do
      assert_text "No tasks in this sprint yet."
      fill_in "New task in Sprint 3", with: "Rate limiting"
      click_button "Create"
      assert_text "Rate limiting"
      assert_text "1 task in total"
    end
    assert_equal [ planned, statuses(:goal_todo) ], Task.find_by!(title: "Rate limiting").then { |task| [ task.sprint, task.status ] }

    within(".side-nav") { click_link "Board" }
    assert_selector ".column h2", text: "To Do"
    assert_no_text "Rate limiting"
    within(".side-nav") { click_link "Backlog" }
    assert_text "The backlog is empty."
  end

  test "move a planned task back to the backlog: its column is unchanged" do
    planned = create_sprint("Sprint 3")
    @project.tasks.create!(title: "TEST-9", creator: @user, status: statuses(:goal_work), sprint: planned)
    visit "/app/projects/#{@project.id}/sprints"

    within(sprint_card("Sprint 3")) { click_button "Move GOAL-1" }
    click_button "Backlog"

    assert_text "GOAL-1 moved to the backlog"
    within(sprint_card("Sprint 3")) { assert_text "No tasks in this sprint yet." }
    task = Task.find_by!(title: "TEST-9")
    assert_equal [ nil, statuses(:goal_work) ], [ task.sprint, task.status ]

    within(".side-nav") { click_link "Backlog" }
    within(".backlog > li", text: "TEST-9") { assert_text "Work" }
  end

  test "active sprint: marked active, collapsed, and its section lists the board's tasks" do
    active = create_sprint("Sprint 1", active: true)
    @project.tasks.create!(title: "On the board", creator: @user, status: statuses(:goal_todo), sprint: active)
    visit "/app/projects/#{@project.id}/sprints"

    within(sprint_card("Sprint 1")) { assert_text "Active" }
    assert_expanded "Sprint 1", false
    assert_no_text "On the board"

    sprint_toggle("Sprint 1").click
    assert_expanded "Sprint 1", true
    within(sprint_card("Sprint 1")) { assert_text "On the board" }
  end

  test "done and carried-over tasks in a sprint section" do
    sprint2 = create_sprint("Sprint 2")
    sprint3 = create_sprint("Sprint 3")
    @project.tasks.create!(title: "GOAL-3 work", creator: @user, status: statuses(:goal_work), sprint: sprint2)
    @project.tasks.create!(title: "GOAL-5 shipped", creator: @user, status: statuses(:goal_done), sprint: sprint2)
    sprint2.carry_over_to(sprint3)
    visit "/app/projects/#{@project.id}/sprints"

    within(sprint_card("Sprint 2")) do
      within(".row-list > li", text: "GOAL-5 shipped") { assert_selector ".chip", text: "Done" }
      within(".row-list > li", text: "GOAL-3 work") do
        assert_selector ".chip", text: "Carried to Sprint 3"
        assert_text "Work"
      end
    end
  end

  test "sprint sections open and close from the keyboard" do
    create_sprint("Sprint 3")
    visit "/app/projects/#{@project.id}/sprints"
    assert_expanded "Sprint 3", true
    toggle = sprint_toggle("Sprint 3")

    execute_script("arguments[0].focus()", toggle)
    toggle.send_keys(:enter)
    assert_expanded "Sprint 3", false
    assert_no_field "New task in Sprint 3"

    toggle.send_keys(:space)
    assert_expanded "Sprint 3", true
    assert_field "New task in Sprint 3"
  end

  test "milestones: create, open with progress, delete and recover" do
    visit "/app/projects/#{@project.id}/milestones"

    fill_in "New milestone", with: "Launch"
    click_button "Create"
    assert_link "Launch"
    milestone = @project.milestones.find_by!(title: "Launch")
    @project.tasks.create!(title: "Ship it", creator: @user, status: statuses(:goal_done), milestone: milestone)
    @project.tasks.create!(title: "Announce it", creator: @user, status: statuses(:goal_todo), milestone: milestone)

    click_link "Launch"
    assert_selector "h1", text: "Launch"
    assert_text "1 of 2 done"
    assert_text "Ship it"
    assert_text "Announce it"

    click_button "Delete milestone"
    within("dialog[open]") { click_button "Delete" }
    assert_text "“Launch” was deleted"
    assert_current_path "/app/projects/#{@project.id}/milestones"
    within("section[aria-labelledby=deleted-milestones]") { assert_text "Launch" }

    click_button "Recover Launch"
    assert_text "“Launch” was recovered"
    assert_link "Launch"
    assert_nil milestone.reload.deleted_at
  end
end
