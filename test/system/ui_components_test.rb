require "application_system_test_case"

# Shared UI components on the test-only fixture page (spec web-client,
# "Accessibility baseline").
class UiComponentsTest < ApplicationSystemTestCase
  setup do
    sign_in users(:one).email_address, "correct horse battery"
    visit "/app/__fixtures/components"
    assert_selector "h1", text: "Component fixtures"
  end

  test "Escape closes a dialog and returns focus to the button that opened it" do
    click_button "New sprint"
    assert_selector "dialog[open]", text: "Sprint name"
    assert_equal "dialog", evaluate_script("document.activeElement.closest('dialog')?.tagName.toLowerCase()"),
      "focus moves into the dialog"
    assert evaluate_script(<<~JS), "the page behind the dialog is covered by the modal backdrop"
      (() => {
        const rect = document.querySelector("main h1").getBoundingClientRect()
        return document.elementFromPoint(rect.left + 2, rect.top + 2)?.closest("dialog") !== null
      })()
    JS

    find("dialog[open]").send_keys(:escape)

    assert_no_selector "dialog[open]"
    assert_equal "New sprint", evaluate_script("document.activeElement.textContent.trim()")
  end

  test "a backdrop click closes the dialog" do
    click_button "New sprint"
    assert_selector "dialog[open]"

    page.driver.browser.action.move_to_location(5, 5).click.perform

    assert_no_selector "dialog[open]"
  end

  test "a menu closes on an outside click and on Escape, and after choosing an item" do
    click_button "Options"
    assert_button "First option"
    assert_selector "button[aria-expanded=true]", text: "Options"

    find("h1").click
    assert_no_button "First option"
    assert_selector "button[aria-expanded=false]", text: "Options"

    click_button "Options"
    assert_button "Second option"
    find("body").send_keys(:escape)
    assert_no_button "Second option"

    click_button "Options"
    click_button "Second option"
    assert_no_button "Second option"
    assert_text "Picked: second"
  end

  test "a toast is announced through a polite live region" do
    click_button "Show toast"

    region = find("[role=status][aria-live=polite]")
    assert region.has_text?("Changes saved")
    assert evaluate_script("document.querySelector('[role=status]').matches(':popover-open')")

    within(region) { click_button "Close" }
    assert_no_text "Changes saved"
  end
end
