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

  test "project cards show their open-task count and link to the board" do
    task("Mine in progress", @one, :goal_work)
    task("Mine to do", @one, :goal_todo, important: true)
    sign_in @one.email_address, "correct horse battery"
    visit "/app"

    assert_selector ".dashboard__date", text: Date.current.day.to_s
    within(".dashboard__project", text: "Goalner") do
      assert_selector ".marker[data-tone]"
      assert_selector ".badge", text: "2"
      within(".tile", text: "Mine to do") { assert_selector ".visually-hidden", text: "Important", visible: :all }
      click_link "Open board"
    end
    assert_current_path "/app/projects/#{@project.id}/board"
  end

  # Spec web-client, dashboard deadlines.
  test "deadlines show date tiles with today highlighted" do
    due_today = task("Due today", @one, :goal_todo, deadline: Time.current.end_of_day - 1.second)
    later = task("Due later", @one, :goal_work, deadline: 3.days.from_now.change(hour: 12))
    sign_in @one.email_address, "correct horse battery"

    { "en" => %w[Sun Mon Tue Wed Thu Fri Sat], "ru" => %w[вс пн вт ср чт пт сб] }.each do |lang, weekdays|
      @one.update!(lang: lang)
      visit "/app"
      assert_selector "h1", text: lang == "en" ? "My tasks" : "Мои задачи"

      within(".dashboard__deadlines") do
        within(".deadline--today", text: "Due today") do
          assert_selector ".deadline__weekday", exact_text: lang == "en" ? "Today" : "Сегодня"
          assert_selector ".deadline__day", exact_text: due_today.deadline.day.to_s
          assert_text "#{due_today.key} · Goalner"
        end
        assert_selector ".deadline--today", count: 1
        within(".deadline", text: "Due later") do
          assert_selector ".deadline__weekday", exact_text: weekdays[later.deadline.wday]
          assert_selector ".deadline__day", exact_text: later.deadline.day.to_s
          assert_text "#{later.key} · Goalner"
        end
      end
    end
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
