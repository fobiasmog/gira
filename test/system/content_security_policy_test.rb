require "application_system_test_case"
require "support/drag_and_drop_helper"
require "support/production_probe"

# Spec web-client, "Strict CSP compatibility": a production build of the SPA
# used end to end under the production Content Security Policy.
class ContentSecurityPolicyTest < ApplicationSystemTestCase
  include DragAndDropHelper

  test "sign in, move a card, edit a description and post a comment with no CSP violation or third-party request" do
    project = projects(:goal)
    task = project.tasks.create!(title: "Policy check", creator: users(:one), status: statuses(:goal_todo))

    production_csp = ProductionProbe.request({ url: "https://goalner.test/app" }).first.dig("headers", "content-security-policy")
    assert_includes production_csp, "style-src 'self'"

    # The browser's log buffer still holds earlier tests' entries.
    page.driver.browser.logs.get(:browser)
    sign_in users(:one).email_address, "correct horse battery"
    visit "/app/projects/#{project.id}/board"
    assert_selector ".column h2", text: "Work"
    assert_equal production_csp, evaluate_async_script(<<~JS)
      const done = arguments[0]
      fetch(location.href).then((response) => done(response.headers.get("Content-Security-Policy")))
    JS
    execute_script(<<~JS)
      window.__violations = []
      document.addEventListener("securitypolicyviolation", (e) => window.__violations.push(`${e.violatedDirective} ${e.blockedURI}`))
    JS

    drag_and_drop(find("[data-drag-item=card]", text: "Policy check").find(".drag-handle", visible: :all), find(".column", text: "Work", match: :first).find("ol"))
    within(".column", text: "Work", match: :first) { assert_text "Policy check" }

    click_link "Policy check"
    editor = find(".description-editor__content")
    editor.click
    editor.send_keys("## Notes", :enter, "- [ ] checked under the policy")
    find("h1", text: "Policy check").click
    Timeout.timeout(5) { sleep 0.1 until task.reload.description.to_s.include?("## Notes") }

    fill_in "Comment", with: "Posted with **no** violations"
    click_button "Post comment"
    within(".comment") { assert_selector "strong", text: "no" }

    assert_empty evaluate_script("window.__violations")
    origins = evaluate_script("performance.getEntriesByType('resource').map((e) => new URL(e.name).origin)").uniq
    assert_equal [ evaluate_script("location.origin") ], origins

    console = page.driver.browser.logs.get(:browser)
    assert_empty console.select { |entry| entry.message.start_with?("security") }, "CSP violations in the console"
    assert_empty console.select { |entry| entry.level == "SEVERE" }.map(&:message), "errors in the console"
  end
end
