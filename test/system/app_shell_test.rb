require "application_system_test_case"

# Spec web-client, "Application shell and navigation" and "Language and
# formatting".
class AppShellTest < ApplicationSystemTestCase
  PASSWORD = "correct horse battery"

  test "reloading a deep task URL shows the same task" do
    task = projects(:goal).tasks.create!(title: "Write the spec", creator: users(:one), status: statuses(:goal_todo))
    sign_in users(:one).email_address, PASSWORD

    visit "/app/projects/#{projects(:goal).id}/tasks/#{task.key}"
    assert_selector "h1", text: "Write the spec"
    assert_text task.key

    page.driver.browser.navigate.refresh
    assert_selector "h1", text: "Write the spec"
  end

  test "navigating between screens does not reload the page" do
    sign_in users(:one).email_address, PASSWORD
    visit "/app"
    assert_link "Dashboard"
    execute_script("window.__sameDocument = true")

    within(".side-nav") { click_link "Goalner", href: "/app/projects/#{projects(:goal).id}/board" }
    within(".side-nav") { click_link "Backlog" }
    assert_current_path "/app/projects/#{projects(:goal).id}/backlog"
    assert evaluate_script("window.__sameDocument === true")
  end

  test "an unknown URL shows the not-found screen with a link to the project list" do
    sign_in users(:one).email_address, PASSWORD

    visit "/app/does-not-exist"
    assert_selector "h1", text: "Page not found"
    click_link "Go to the project list"
    assert_current_path "/app/projects"
  end

  test "a task in a project the user does not belong to shows the not-found screen" do
    task = projects(:side).tasks.create!(title: "Secret plans", creator: users(:two), status: statuses(:side_todo))
    sign_in users(:one).email_address, PASSWORD

    visit "/app/projects/#{projects(:side).id}/tasks/#{task.key}"
    assert_selector "h1", text: "Page not found"
    assert_no_text "Secret plans"
  end

  test "the shell renders in Russian for a Russian-language user" do
    users(:one).update!(lang: "ru")
    sign_in users(:one).email_address, PASSWORD

    visit "/app"
    assert_link "Главная"
    assert_link "Новый проект"
    assert_equal "ru", evaluate_script("document.documentElement.lang")
  end

  test "on a narrow screen the navigation opens as a dialog" do
    sign_in users(:one).email_address, PASSWORD
    page.driver.browser.manage.window.resize_to(600, 900)
    visit "/app"

    assert_no_link "Dashboard"
    click_button "Menu"
    within("dialog[open]") { click_link "Goalner", href: "/app/projects/#{projects(:goal).id}/board" }
    assert_no_selector "dialog[open]"
    assert_current_path "/app/projects/#{projects(:goal).id}/board"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end
end
