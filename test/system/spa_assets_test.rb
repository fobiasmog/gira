require "application_system_test_case"

# Spec web-client, "Strict CSP compatibility": fonts and icons come from the
# application's origin and actually render.
class SpaAssetsTest < ApplicationSystemTestCase
  test "icons from the sprite and the Rubik font render, with no third-party requests" do
    sign_in users(:one).email_address, "correct horse battery"
    visit "/app"

    assert_selector "svg.icon use", minimum: 1
    icon_width = evaluate_async_script(<<~JS)
      const done = arguments[0]
      const use = document.querySelector("svg.icon use")
      const measure = (tries) => {
        const width = use.getBBox().width
        if (width > 0 || tries === 0) done(width)
        else setTimeout(() => measure(tries - 1), 100)
      }
      measure(30)
    JS
    assert_operator icon_width, :>, 0, "the icon's <use> did not resolve to a sprite symbol"

    assert evaluate_async_script(<<~JS), "Rubik did not load"
      const done = arguments[0]
      document.fonts.load('16px "Rubik"').then(() => done(document.fonts.check('16px "Rubik"')))
    JS

    origins = evaluate_script(<<~JS)
      performance.getEntriesByType("resource").map((entry) => new URL(entry.name).origin)
    JS
    assert_equal [ page.evaluate_script("location.origin") ], origins.uniq
  end
end
