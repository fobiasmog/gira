require "application_system_test_case"

# Spec web-client, "Accessibility baseline": every screen's controls have
# accessible names.
class AccessibilityTest < ApplicationSystemTestCase
  # Problems on the current page: controls without an accessible name, and
  # images without alt text. Includes controls inside closed menus and dialogs.
  PROBLEMS = <<~JS
    (() => {
      const describe = (el) => el.outerHTML.slice(0, 120)
      const named = (el) => (el.getAttribute("aria-label") || "").trim() ||
        (el.getAttribute("aria-labelledby") || "").split(/\\s+/).some((id) => document.getElementById(id)?.textContent.trim())
      const problems = []
      for (const el of document.querySelectorAll("#app button, #app a[href], #app [role=button]")) {
        if (!el.textContent.trim() && !named(el)) problems.push(`unnamed control: ${describe(el)}`)
      }
      for (const el of document.querySelectorAll("#app input:not([type=hidden]), #app select, #app textarea, #app [contenteditable=true]")) {
        if (!(el.labels && el.labels.length) && !named(el)) problems.push(`unlabelled field: ${describe(el)}`)
      }
      for (const el of document.querySelectorAll("#app img")) {
        if (!el.hasAttribute("alt")) problems.push(`image without alt: ${describe(el)}`)
      }
      for (const el of document.querySelectorAll("#app dialog")) {
        if (!named(el)) problems.push(`unnamed dialog: ${describe(el)}`)
      }
      return problems
    })()
  JS

  setup do
    @project = projects(:goal)
    @user = users(:one)
    label = @project.labels.create!(title: "Backend")
    change = @project.project_changes.create!(name: "add-labels")
    @task = @project.tasks.create!(title: "Accessible task", creator: @user, status: statuses(:goal_todo), label: label, change: change,
      assignee: users(:two), deadline: 2.days.from_now, important: true, description: "- [ ] item")
    @project.tasks.create!(title: "Subtask", creator: @user, parent: @task, status: statuses(:goal_todo))
    @task.comments.create!(author: @user, body: "A comment")
    @project.tasks.create!(title: "Other task", creator: @user)
    @project.tasks.create!(title: "Done in no change", creator: @user, status: statuses(:goal_done))
    @archived_change = @project.project_changes.create!(name: "export-csv", idea: "An archived idea")
    @archived_change.archive!
    Change::Import.new(project: @project, user: @user, name: "fix-login",
      artifacts: { "tasks" => "## 1. Form\n- [ ] 1.1 Field\n", "proposal" => "# Why\n", "specs" => { "login" => "## ADDED\n" } }).run!
    @project.project_changes.find_by!(name: "fix-login").comments.create!(author: @user, body: "A change comment")
    @archived = @project.tasks.create!(title: "Archived task", creator: @user, status: statuses(:goal_done))
    @archived.archive!
    @project.invitations.create!(email: "pending@example.com", inviter: @user, token_digest: "x", expires_at: 1.day.from_now)
    Announcement.create!(body: "News for everyone")
    agent = create_agent(@project, name: "Accessible agent")
    issue_agent_token(agent, issuer: @user)
    create_agent(@project, name: "Deleted agent").delete!
  end

  test "every screen names its controls, labels its fields and gives images alt text" do
    sign_in @user.email_address, "correct horse battery"
    base = "/app/projects/#{@project.id}"
    screens = {
      "/app" => "My tasks",
      "/app/projects" => "Projects",
      "/app/projects/new" => "New project",
      "#{base}/board/changes/add-labels" => "Accessible task",
      "#{base}/list/changes/add-labels" => "Accessible task",
      "#{base}/board/other" => "Other task",
      "#{base}/board/changes/export-csv" => "is archived or does not exist",
      "#{base}/changes" => "Accessible task",
      "#{base}/changes/fix-login" => "A change comment",
      "#{base}/changes/#{@archived_change.id}" => "An archived idea",
      "#{base}/changes/no-such-change" => "is archived or does not exist",
      "#{base}/members" => "pending@example.com",
      "#{base}/agents" => "Accessible agent",
      "#{base}/settings" => "Project settings",
      "#{base}/archive" => "Archived task",
      "#{base}/archive/#{@archived.id}" => "Archived task",
      "#{base}/tasks/#{@task.key}" => "A comment",
      "/app/settings/profile" => "Contacts",
      "/app/settings/security" => "Change password",
      "/app/settings/api-tokens" => "Bot",
      "/app/settings/connected-apps" => "You have not connected any apps.",
      "/app/nowhere" => "Page not found"
    }

    problems = screens.flat_map do |path, marker|
      visit path
      assert_text marker
      evaluate_script(PROBLEMS).map { |problem| "#{path}: #{problem}" }
    end

    assert_empty problems
  end

  test "close the new change dialog with Escape: focus returns to the new change button" do
    sign_in @user.email_address, "correct horse battery"
    visit "/app/projects/#{@project.id}/changes"

    click_button "New change"
    assert_selector "dialog[open]", text: "Name"
    assert_empty evaluate_script(PROBLEMS)
    find_field("Name").send_keys(:escape)

    assert_no_selector "dialog[open]"
    assert_equal "New change", evaluate_script("document.activeElement.textContent.trim()")
  end

  test "the OAuth consent page names its controls and labels its fields" do
    client = oauth_applications(:claude_code)
    sign_in @user.email_address, "correct horse battery"
    visit "/oauth/authorize?" + { response_type: "code", client_id: client.uid, redirect_uri: "http://localhost:4000/callback",
      scope: "read write", state: "s", code_challenge: "x" * 43, code_challenge_method: "S256" }.to_query

    assert_selector "h1", text: "localhost wants to access your Goalner account"
    assert_empty evaluate_script(PROBLEMS.gsub("#app", "main"))
    assert_empty unfocusable_indicators(12), "the consent page has focusable elements without a visible focus indicator"
  end

  test "the narrow-screen menu dialog and the feedback dialog are named" do
    sign_in @user.email_address, "correct horse battery"
    page.driver.browser.manage.window.resize_to(600, 900)
    visit "/app"

    click_button "Menu"
    assert_selector "dialog[open][aria-labelledby]"
    assert_empty evaluate_script(PROBLEMS)
    within("dialog[open]") { click_button "Write to us" }
    assert_selector "dialog[open]", text: "Topic"
    assert_empty evaluate_script(PROBLEMS)
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end

  # Tabs through the page and returns the focused elements that show no focus
  # indicator (an outline on the element, or on the card, editor, comment
  # composer or new-task bar around it).
  def unfocusable_indicators(steps)
    find("body").click
    misses = []
    steps.times do
      page.driver.browser.action.send_keys(:tab).perform
      miss = evaluate_script(<<~JS)
        (() => {
          const el = document.activeElement
          if (!el || el === document.body) return null
          const shown = (node) => node && getComputedStyle(node).outlineStyle !== "none"
          return shown(el) || shown(el.closest(".card, .description-editor, .composer, .new-bar")) ? null : el.outerHTML.slice(0, 100)
        })()
      JS
      misses << miss if miss
    end
    misses.uniq
  end

  test "keyboard walkthrough: every element reached with Tab shows where focus is" do
    sign_in @user.email_address, "correct horse battery"
    base = "/app/projects/#{@project.id}"
    [ "#{base}/board", "#{base}/list", "#{base}/tasks/#{@task.key}", "#{base}/changes", "#{base}/members", "/app/settings/profile" ].each do |path|
      visit path
      assert_selector "h1"
      assert_empty unfocusable_indicators(40), "#{path} has focusable elements without a visible focus indicator"
    end
  end
end
