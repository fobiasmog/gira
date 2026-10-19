require "application_system_test_case"
require "support/drag_and_drop_helper"

# Spec board-drag-and-drop on the kanban board.
class BoardDragTest < ApplicationSystemTestCase
  include DragAndDropHelper

  setup do
    @project = projects(:goal)
    @user = users(:one)
  end

  def task(title, status)
    @project.tasks.create!(title: title, creator: @user, status: statuses(status))
  end

  def visit_board
    sign_in @user.email_address, "correct horse battery"
    visit "/app/projects/#{@project.id}/board"
    assert_selector ".column h2", text: "Done"
  end

  def column(title)
    find(".column", text: title, match: :first) { |c| c.find("h2").text == title }
  end

  def cards(title)
    column(title).all("[data-drag-item=card] .card__title").map(&:text)
  end

  def card_item(title)
    find("[data-drag-item=card]", text: title)
  end

  def card_handle(title)
    card_item(title).find(".drag-handle", visible: :all)
  end

  test "move to another column, between two cards, and it stays after reload" do
    task("Alpha", :goal_work)
    task("Beta", :goal_work)
    task("Gamma", :goal_todo)
    moved = task("Delta", :goal_todo)
    visit_board

    drag_and_drop(card_handle("Delta"), column("Work").find("ol"), before: card_item("Beta"))

    within(column("Work")) { assert_text "Delta" }
    assert_equal [ "Alpha", "Delta", "Beta" ], cards("Work")
    assert_equal [ "Gamma" ], cards("To Do")
    assert_text moved.key

    page.driver.browser.navigate.refresh
    assert_selector ".column h2", text: "Work"
    assert_equal [ "Alpha", "Delta", "Beta" ], cards("Work")
    assert_equal [ statuses(:goal_work).id, 1 ], [ moved.reload.status_id, moved.position ]
  end

  test "move within a column" do
    task("First", :goal_todo)
    task("Second", :goal_todo)
    task("Third", :goal_todo)
    visit_board

    drag_and_drop(card_handle("Third"), column("To Do").find("ol"), before: card_item("First"))

    assert_selector "[data-drag-item=card]:first-of-type", text: "Third"
    assert_equal [ "Third", "First", "Second" ], cards("To Do")
    assert_equal [ "Third", "First", "Second" ], @project.tasks.where(status: statuses(:goal_todo)).order(:position).map(&:title)
  end

  test "dragging outside the handle starts no drag" do
    task("Hold me", :goal_todo)
    visit_board
    watch_requests("/placement")

    title = card_item("Hold me").find(".card__title")
    assert_equal false, evaluate_script("arguments[0].closest('[draggable=true]') !== null", title)
    page.driver.browser.action.click_and_hold(title.native).move_to(column("Done").native).release.perform

    assert_equal [ "Hold me" ], cards("To Do")
    assert_equal 0, watched_requests
  end

  test "move a column; the last column stays the done column" do
    Board.new(@project).add_column(title: "Review")
    visit_board
    assert_equal [ "To Do", "Work", "Review", "Done" ], all(".column h2").map(&:text)

    board = find(".board")
    review_handle = column("Review").find(".drag-handle", visible: :all)
    drag_and_drop(review_handle, board, before: find("[data-drag-item=column]", text: "Work", match: :first) { |c| c.find("h2").text == "Work" })

    assert_selector "[data-drag-item=column]:nth-of-type(2) h2", text: "Review"
    assert_equal [ "To Do", "Review", "Work", "Done" ], all(".column h2").map(&:text)
    page.driver.browser.navigate.refresh
    assert_selector ".column h2", text: "Review"
    assert_equal [ "To Do", "Review", "Work", "Done" ], all(".column h2").map(&:text)
    assert_equal [ "Done" ], @project.statuses.reload.select(&:done).map(&:title)
  end

  test "moving the done column to the front makes the new last column the done column" do
    visit_board

    drag_and_drop(column("Done").find(".drag-handle", visible: :all), find(".board"), before: find("[data-drag-item=column]", text: "To Do", match: :first))

    assert_selector "[data-drag-item=column]:first-of-type h2", text: "Done"
    assert_equal [ "Done", "To Do", "Work" ], all(".column h2").map(&:text)
    assert_equal [ "Work" ], @project.statuses.reload.select(&:done).map(&:title)
  end

  test "network failure: the card returns and an error is shown" do
    task("Fragile", :goal_todo)
    visit_board
    watch_requests("/placement", fail: true)

    drag_and_drop(card_handle("Fragile"), column("Work").find("ol"))

    assert_text "The move could not be saved, so the item is back where it was."
    assert_equal [ "Fragile" ], cards("To Do")
    assert_empty cards("Work")
    assert_equal 1, watched_requests
    assert_equal statuses(:goal_todo), Task.find_by!(title: "Fragile").status
  end

  test "dropping a link from another tab changes nothing and does not navigate" do
    task("Stay", :goal_todo)
    visit_board
    watch_requests("/api/")
    url = current_url

    assert drop_foreign_link(column("Work").find("ol"), "https://example.com/elsewhere"), "the page must cancel the browser's drop action"

    assert_equal url, current_url
    assert_equal [ "Stay" ], cards("To Do")
    assert_empty cards("Work")
    assert_equal 0, watched_requests
  end

  test "Escape during a drag leaves the card and sends no request" do
    task("Escape me", :goal_todo)
    visit_board
    watch_requests("/placement")

    drag_and_cancel(card_handle("Escape me"), column("Work").find("ol"))

    assert_no_selector ".drop-indicator"
    assert_no_selector ".is-dragging"
    assert_equal [ "Escape me" ], cards("To Do")
    assert_equal 0, watched_requests
  end

  test "holding a card near the right edge scrolls the board to reach a hidden column" do
    task("Traveller", :goal_todo)
    3.times { |i| Board.new(@project).add_column(title: "Extra #{i}") }
    page.driver.browser.manage.window.resize_to(1100, 900)
    visit_board

    scrolled = evaluate_async_script(<<~JS, card_handle("Traveller"), find(".board"))
      const [handle, board, done] = arguments
      const data = new DataTransfer()
      const r = board.getBoundingClientRect()
      const fire = (el, type, x, y) => el.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: data, clientX: x, clientY: y }))
      fire(handle, "dragstart", 0, 0)
      const timer = setInterval(() => fire(board.querySelector(".column ol"), "dragover", r.right - 5, r.top + 100), 50)
      setTimeout(() => { clearInterval(timer); fire(handle, "dragend", 0, 0); done(board.scrollLeft) }, 800)
    JS

    assert_operator scrolled, :>, 0
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end
end
