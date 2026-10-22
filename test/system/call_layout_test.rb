require "support/call_system_test_case"

# Where the call is shown (spec team-call): the pane on wide screens, the
# full-screen overlay on narrow ones, and the bar and tab on both.
class CallLayoutTest < CallSystemTestCase
  setup do
    @project = projects(:goal)
    sign_in_as users(:one)
  end

  test "pane appears: the board narrows and every column stays reachable" do
    open_board
    board_width = evaluate_script("document.querySelector('.board').clientWidth")

    join_call

    assert_selector "aside.call-pane", text: "Goalner"
    assert_equal 320, pane_width
    assert_in_delta board_width - 320, evaluate_script("document.querySelector('.board').clientWidth"), 2
    assert evaluate_script(<<~JS), "the last column scrolls into view left of the pane"
      (() => {
        const board = document.querySelector(".board")
        board.scrollLeft = board.scrollWidth
        const add = board.querySelector(".board__add").getBoundingClientRect()
        return add.right <= document.querySelector(".call-pane").getBoundingClientRect().left
      })()
    JS
  end

  test "resize with the keyboard; the width is remembered" do
    open_board
    join_call
    separator = find("[role=separator]")
    assert_equal [ "320", "240", "480" ], [ separator["aria-valuenow"], separator["aria-valuemin"], separator["aria-valuemax"] ]

    separator.send_keys(:left)

    assert_selector "[role=separator][aria-valuenow='336']"
    assert_equal 336, pane_width
    separator.send_keys(:right, :right)
    assert_selector "[role=separator][aria-valuenow='304']"

    click_button "Shrink the call"
    click_button "Expand the call"
    assert_equal 304, pane_width

    visit current_url
    join_call
    assert_equal 304, pane_width
  end

  test "width limits: dragging the edge stops at 480 and 240 pixels" do
    open_board
    join_call

    page.driver.browser.action.drag_and_drop_by(find("[role=separator]").native, -400, 0).perform
    assert_selector "[role=separator][aria-valuenow='480']"
    assert_equal 480, pane_width

    page.driver.browser.action.drag_and_drop_by(find("[role=separator]").native, 300, 0).perform
    assert_selector "[role=separator][aria-valuenow='240']"
    assert_equal 240, pane_width
  end

  test "shrink the pane to the bar: the board takes the full width, and microphone and camera stay as they were" do
    open_board
    board_width = evaluate_script("document.querySelector('.board').clientWidth")
    join_call
    click_button "Microphone"
    assert_selector "button[aria-pressed=false]", text: "Microphone"

    click_button "Shrink the call"

    assert_no_selector "aside.call-pane"
    within(".call-bar") do
      assert_link "Goalner"
      assert_text "1 participant"
      assert_selector "button[aria-pressed=false]", text: "Microphone"
      assert_selector "button[aria-pressed=true]", text: "Camera"
    end
    assert_equal board_width, evaluate_script("document.querySelector('.board').clientWidth")
  end

  test "hide the bar with the microphone off; the tab brings back the bar and then the expanded call" do
    open_board
    join_call
    click_button "Shrink the call"
    within(".call-bar") { click_button "Microphone" }

    click_button "Hide the call bar"

    assert_no_selector ".call-bar"
    tab = find("button.call-tab")
    assert_equal "Show the call bar, 1 participant, Microphone off", tab["aria-label"]
    within(tab) { assert_text "1" }
    assert_button "In call"

    tab.click
    assert_selector ".call-bar"
    click_button "Expand the call"
    assert_selector "aside.call-pane"
    assert_selector "button[aria-pressed=false]", text: "Microphone"
  end

  test "the sound goes on in the bar and the tab, where no tiles are shown" do
    open_board
    join_call
    as(users(:two)) { open_board; join_call }
    assert_hears

    click_button "Shrink the call"
    assert_no_selector ".tile"
    assert_hears

    click_button "Hide the call bar"
    assert_selector "button.call-tab"
    assert_hears
  end

  test "content stays reachable above the bar and the tab, on wide and narrow screens" do
    40.times { |i| @project.tasks.create!(title: "Backlog task #{i + 1}", creator: users(:one), status: statuses(:goal_todo)) }
    open_board
    join_call
    click_button "Shrink the call"

    within(".side-nav") { click_link "Backlog" }
    assert_selector ".backlog > li", text: "Backlog task 40"
    assert_last_task_above ".call-bar"

    on_narrow_screen do
      assert_last_task_above ".call-bar"
      click_button "Hide the call bar"
      assert_last_task_above ".call-tab"
    end
  end

  test "join on a phone: the call covers the whole screen" do
    on_narrow_screen do
      open_board
      join_call

      overlay = find("dialog.call-overlay[open]")
      within(overlay) do
        assert_link "Goalner"
        assert_selector ".tile", text: "You"
        assert_button "Microphone"
        assert_button "Camera"
        assert_button "Leave"
      end
      assert_equal [ 0, 0, 390 ], evaluate_script(<<~JS).map(&:round)
        (() => { const r = document.querySelector("dialog.call-overlay").getBoundingClientRect(); return [r.left, r.top, r.width] })()
      JS
      assert_equal "dialog", evaluate_script("document.activeElement.closest('dialog')?.tagName.toLowerCase()"), "focus is inside"
    end
  end

  test "escape shrinks the call to the bar, and the board can be used" do
    on_narrow_screen do
      open_board
      join_call

      find("dialog.call-overlay[open]").send_keys(:escape)

      assert_no_selector "dialog.call-overlay"
      assert_selector ".call-bar"
      assert_button "In call"
      click_link "List"
      assert_current_path "/app/projects/#{@project.id}/list"
      within(".board-header") { assert_button "In call" }
      assert_selector ".call-bar"
      assert_in_call @project, users(:one)
    end
  end

  private
    def assert_last_task_above(dock)
      execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")
      gap = evaluate_script(<<~JS)
        (() => {
          const rows = document.querySelectorAll(".backlog > li")
          return document.querySelector("#{dock}").getBoundingClientRect().top - rows[rows.length - 1].getBoundingClientRect().bottom
        })()
      JS
      assert_operator gap, :>=, 0, "the last task is hidden under #{dock}"
    end
end
