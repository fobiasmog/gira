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

  # Spec web-client, "Project switcher".
  test "switch to another project from the project switcher" do
    other = Project.create!(title: "Mobile app", short_name: "MOB", owner: users(:one))
    sign_in users(:one).email_address, PASSWORD
    visit "/app/projects/#{projects(:goal).id}/board"

    within(".side-nav") { click_button "Switch project: Goalner" }
    within(".menu:popover-open") do
      assert_selector "a[aria-current=page]", text: "Goalner"
      assert_link "New project"
      click_link "Mobile app"
    end

    assert_current_path "/app/projects/#{other.id}/board"
    assert_selector ".side-nav .switcher", text: "Mobile app"
    assert_selector ".side-nav .switcher", text: "MOB"
    assert_no_selector ".menu:popover-open"
  end

  test "create a project from the project switcher" do
    sign_in users(:one).email_address, PASSWORD
    visit "/app/projects/#{projects(:goal).id}/board"

    within(".side-nav") { click_button "Switch project: Goalner" }
    within(".menu:popover-open") { click_link "New project" }

    assert_current_path "/app/projects/new"
    assert_selector "h1", text: "New project"
  end

  test "without an open project the switcher invites the user to choose one" do
    sign_in users(:one).email_address, PASSWORD
    visit "/app"

    within(".side-nav") do
      assert_button "Choose a project"
      assert_link "Goalner"
      assert_no_link "Board"
      assert_no_link "Backlog"
      assert_no_link "Team"
    end
  end

  test "the project switcher works in the narrow-screen menu" do
    other = Project.create!(title: "Mobile app", short_name: "MOB", owner: users(:one))
    sign_in users(:one).email_address, PASSWORD
    page.driver.browser.manage.window.resize_to(600, 900)
    visit "/app"

    click_button "Menu"
    within("dialog[open]") do
      assert_no_link "Backlog"
      click_button "Choose a project"
    end
    within(".menu:popover-open") { click_link "Mobile app" }

    assert_no_selector "dialog[open]"
    assert_current_path "/app/projects/#{other.id}/board"
    click_button "Menu"
    within("dialog[open]") do
      assert_selector ".switcher", text: "Mobile app"
      assert_link "Backlog"
    end
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end

  test "the header shows where the user is in the project" do
    task = projects(:goal).tasks.create!(title: "Write the spec", creator: users(:one), status: statuses(:goal_todo))
    sign_in users(:one).email_address, PASSWORD

    visit "/app/projects/#{projects(:goal).id}/tasks/#{task.key}"
    assert_selector "h1", text: "Write the spec"
    within("nav[aria-label=Breadcrumb]") do
      assert_text "Goalner / Board / #{task.key}"
      assert_selector "[aria-current=page]", text: task.key
      click_link "Board"
    end
    assert_current_path "/app/projects/#{projects(:goal).id}/board"
    within("nav[aria-label=Breadcrumb]") { assert_text "Goalner / Board" }

    visit "/app"
    assert_selector "h1", text: "My tasks"
    assert_no_selector "nav[aria-label=Breadcrumb]"
  end

  test "the user menu shows the first name, opens and signs out" do
    sign_in users(:one).email_address, PASSWORD
    visit "/app"

    within(".shell__header") do
      assert_selector ".user-button__name", exact_text: "User"
      click_button "User One"
    end
    within(".menu:popover-open") { click_button "Sign out" }

    assert_link "Sign in"
    visit "/app"
    assert_current_path new_session_path
  end

  # Spec web-client, "Collapsible sidebar".
  test "collapse the sidebar to icons and navigate from the rail" do
    board = "/app/projects/#{projects(:goal).id}/board"
    sign_in users(:one).email_address, PASSWORD
    visit board
    main_width = find(".shell__main").evaluate_script("this.offsetWidth")

    click_button "Collapse menu"
    assert_sidebar_width 64
    assert_operator find(".shell__main").evaluate_script("this.offsetWidth"), :>, main_width
    within(".side-nav") do
      assert_equal 1, label_width("Backlog")
      assert_no_link "Goalner", href: board
      assert_link "Dashboard"
      click_link "Backlog"
    end

    assert_current_path "/app/projects/#{projects(:goal).id}/backlog"
    assert_selector ".side-nav a[aria-current=page][title=Backlog]"
  end

  test "switch project from the collapsed sidebar" do
    other = Project.create!(title: "Mobile app", short_name: "MOB", owner: users(:one))
    sign_in users(:one).email_address, PASSWORD
    visit "/app/projects/#{projects(:goal).id}/board"

    click_button "Collapse menu"
    within(".side-nav") { click_button "Switch project: Goalner" }
    within(".menu:popover-open") { click_link "Mobile app" }

    assert_current_path "/app/projects/#{other.id}/board"
    assert_selector ".side-nav .switcher[title='Mobile app']"
  end

  test "expanding the sidebar restores the labels and keeps focus on the toggle" do
    sign_in users(:one).email_address, PASSWORD
    visit "/app/projects/#{projects(:goal).id}/board"

    click_button "Collapse menu"
    assert_sidebar_width 64
    click_button "Expand menu"

    assert_sidebar_width 256
    within(".side-nav") do
      assert_operator label_width("Backlog"), :>, 1
      assert_link "Goalner", href: "/app/projects/#{projects(:goal).id}/board"
    end
    assert_equal "Collapse menu", evaluate_script("document.activeElement.textContent.trim()")
  end

  test "the collapsed sidebar is remembered after a reload" do
    sign_in users(:one).email_address, PASSWORD
    visit "/app"

    click_button "Collapse menu"
    assert_button "Expand menu"
    page.driver.browser.navigate.refresh

    assert_button "Expand menu"
    assert_sidebar_width 64
  end

  test "the narrow-screen menu is never collapsed" do
    sign_in users(:one).email_address, PASSWORD
    visit "/app/projects/#{projects(:goal).id}/board"
    click_button "Collapse menu"
    assert_button "Expand menu"

    page.driver.browser.manage.window.resize_to(600, 900)
    click_button "Menu"
    within("dialog[open]") do
      assert_operator label_width("Backlog"), :>, 1
      assert_link "Goalner", href: "/app/projects/#{projects(:goal).id}/board"
      assert_no_button "Collapse menu"
      assert_no_button "Expand menu"
    end
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end

  private
    # Waits out the width transition.
    def assert_sidebar_width(width)
      assert_selector(".shell__sidebar") { |aside| aside.evaluate_script("this.getBoundingClientRect().width") == width }
    end

    # The rendered width of a navigation link's label: 1px when it is there
    # for screen readers only.
    def label_width(link)
      find_link(link).find("span", visible: :all).evaluate_script("this.getBoundingClientRect().width")
    end
end
