require "application_system_test_case"
require "support/production_probe"

# Spec api-documentation, "Trying requests from the documentation" and
# "Documentation page security": the built viewer under the production
# Content Security Policy. two is a member of goal; fixture token values are
# "glnr_" followed by the fixture name.
class ApiDocsTest < ApplicationSystemTestCase
  PASSWORD = "correct horse battery"

  setup do
    sign_in users(:two).email_address, PASSWORD
  end

  def open_docs
    visit "/api/docs"
    assert_selector ".opblock-summary-path", text: "/api/me"
  end

  def expand(path, method: "get")
    find(".opblock-#{method} .opblock-summary-path", text: path, exact_text: true).click
  end

  def authorize(token)
    find("button.authorize").click
    within(".modal-ux") do
      find("input").fill_in with: token
      click_button "Authorize"
      click_button "Close"
    end
  end

  def try_it_out
    click_button "Try it out"
    click_button "Execute"
  end

  def live_status
    find(".live-responses-table tbody .response-col_status").text.to_i
  end

  test "no violations: open, expand, authorize and execute under the production policy" do
    production_csp = ProductionProbe.request({ url: "https://goalner.test/api/docs" }).first.dig("headers", "content-security-policy")
    assert_includes production_csp, "script-src 'self'"

    # The browser's log buffer still holds earlier tests' entries.
    page.driver.browser.logs.get(:browser)
    open_docs
    assert_equal production_csp, evaluate_async_script(<<~JS)
      const done = arguments[0]
      fetch(location.href).then((response) => done(response.headers.get("Content-Security-Policy")))
    JS
    execute_script(<<~JS)
      window.__violations = []
      document.addEventListener("securitypolicyviolation", (e) => window.__violations.push(`${e.violatedDirective} ${e.blockedURI}`))
    JS

    expand "/api/me"
    authorize "glnr_two_goal_read_write"
    try_it_out
    assert_equal 200, live_status
    assert_text users(:two).email_address

    assert_empty evaluate_script("window.__violations")
    origins = evaluate_script("performance.getEntriesByType('resource').map((e) => new URL(e.name).origin)").uniq
    assert_equal [ evaluate_script("location.origin") ], origins

    console = page.driver.browser.logs.get(:browser)
    assert_empty console.select { |entry| entry.message.start_with?("security") }, "CSP violations in the console"
    assert_empty console.select { |entry| entry.level == "SEVERE" }.map(&:message), "errors in the console"
  end

  test "try without a token: 401, although the user is signed in" do
    open_docs
    expand "/api/me"

    try_it_out

    assert_equal 401, live_status
    assert_text "invalid_token"
  end

  test "token not kept: after a reload no token is entered, and none is stored" do
    open_docs
    authorize "glnr_two_goal_read_write"
    assert_selector "button.authorize.locked"

    refresh
    assert_selector ".opblock-summary-path", text: "/api/me"

    assert_selector "button.authorize.unlocked"
    stored = evaluate_script("JSON.stringify({ local: { ...localStorage }, session: { ...sessionStorage } })")
    assert_no_match(/glnr_/, stored)
  end

  test "try with a token: create a task in GOAL, attributed to the token's owner" do
    open_docs
    authorize "glnr_two_goal_read_write"
    expand "/api/projects/{project_id}/tasks", method: "post"
    click_button "Try it out"

    find("input[placeholder=project_id]").fill_in with: projects(:goal).id
    find("textarea.body-param__text").fill_in with: { title: "Tried from the docs" }.to_json
    click_button "Execute"

    assert_equal 201, live_status
    task = projects(:goal).tasks.find_by!(title: "Tried from the docs")
    assert_equal users(:two), task.creator
  end

  test "the header links back to the API tokens settings" do
    open_docs

    click_link "Your API tokens"

    assert_current_path "/app/settings/api-tokens"
    assert_text "Create a token"
  end
end
