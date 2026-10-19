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
