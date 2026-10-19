require "application_system_test_case"

# Spec web-client: dashboard, announcements and feedback.
class DashboardTest < ApplicationSystemTestCase
  setup do
    @project = projects(:goal)
    @one = users(:one)
    @two = users(:two)
  end

  def task(title, assignee, status, **attributes)
    @project.tasks.create!(title: title, creator: @one, assignee: assignee, status: status && statuses(status), **attributes)
  end

  test "the dashboard lists my open tasks by project and column, and my deadlines" do
    task("Mine in progress", @one, :goal_work, deadline: 2.days.from_now, important: true)
    task("Mine in backlog", @one, nil)
    task("Mine and done", @one, :goal_done)
    task("Not mine", @two, :goal_todo)
    sign_in @one.email_address, "correct horse battery"

    visit "/app"
    assert_selector "h1", text: "My tasks"
    within(".dashboard__project", text: "Goalner") do
      assert_text(/Work · 1 task/i)
      assert_text(/Backlog · 1 task/i)
      assert_link "Mine in progress"
      assert_link "Mine in backlog"
      assert_no_text "Mine and done"
      assert_no_text "Not mine"
    end
    within(".dashboard__deadlines") { assert_link text: "Mine in progress" }
  end

  test "switch to a teammate's tasks" do
    task("Mine", @one, :goal_todo)
    task("Theirs", @two, :goal_todo)
    sign_in @one.email_address, "correct horse battery"
    visit "/app"
    assert_link "Mine"

    select "User Two", from: "Show the tasks of"

    assert_selector "h1", text: "User Two's tasks"
    assert_current_path "/app/?user=#{@two.id}"
    assert_link "Theirs"
    assert_no_link "Mine"

    select "Me", from: "Show the tasks of"
    assert_selector "h1", text: "My tasks"
    assert_link "Mine"
  end

  test "announcements are shown formatted and can all be dismissed" do
    Announcement.create!(body: "**Big** news: the new client is here")
    Announcement.create!(body: "Second item")
    sign_in @one.email_address, "correct horse battery"
    visit "/app"

    within(".announcements") do
      assert_selector "strong", text: "Big"
      assert_text "Second item"
      click_button "Dismiss all"
    end
    assert_no_selector ".announcements"

    page.driver.browser.navigate.refresh
    assert_selector "h1", text: "My tasks"
    assert_no_selector ".announcements"
    assert_equal 2, AnnouncementDismissal.where(user: @one).count
  end

  test "send feedback" do
    sign_in @one.email_address, "correct horse battery"
    visit "/app"

    within(".side-nav") { click_button "Write to us" }
    within("dialog[open]") do
      select "A suggestion", from: "Topic"
      fill_in "Message", with: "Please add a dark theme"
      click_button "Send"
    end

    assert_text "Thank you for your feedback!"
    assert_no_selector "dialog[open]"
    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    assert_includes mail.body.decoded, "Please add a dark theme"
    assert_includes mail.body.decoded, "A suggestion"
  end
end
