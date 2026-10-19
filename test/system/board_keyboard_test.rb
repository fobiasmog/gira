require "application_system_test_case"

# Spec board-drag-and-drop, "Keyboard moves".
class BoardKeyboardTest < ApplicationSystemTestCase
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

  def cards(title)
    find(".column", text: title, match: :first) { |c| c.find("h2").text == title }
      .all("[data-drag-item=card] .card__title").map(&:text)
  end

  def focus_card(title)
    find("[data-drag-item=card] .card__title", text: title).tap { |link| execute_script("arguments[0].focus()", link) }
  end

  def focused_text
    evaluate_script("document.activeElement.textContent.trim()")
  end

  def announcement
    find("[aria-live=polite][aria-atomic=true]", visible: :all).text(:all)
  end

  test "move right by keyboard: to the end of the next column, focus kept, move announced" do
    task("Work one", :goal_work)
    task("Work two", :goal_work)
    task("Todo first", :goal_todo)
    moved = task("Todo second", :goal_todo)
    assert_equal "GOAL-4", moved.key
    visit_board

    focus_card("Todo second").send_keys([ :alt, :arrow_right ])

    within(".column", text: "Work", match: :first) { assert_text "Todo second" }
    assert_equal [ "Work one", "Work two", "Todo second" ], cards("Work")
    assert_equal "Todo second", focused_text
    assert_equal "GOAL-4 moved to Work, position 3", announcement
    assert_equal [ statuses(:goal_work).id, 2 ], [ moved.reload.status_id, moved.position ]
  end

  test "Alt+Up and Alt+Down move within the column; Alt+Left moves to the previous column" do
    task("One", :goal_work)
    task("Two", :goal_work)
    task("Three", :goal_work)
    visit_board

    focus_card("Three").send_keys([ :alt, :arrow_up ])
    assert_selector ".column [data-drag-item=card]:nth-of-type(2)", text: "Three"
    assert_equal [ "One", "Three", "Two" ], cards("Work")
    assert_equal "GOAL-3 moved to Work, position 2", announcement

    focus_card("One").send_keys([ :alt, :arrow_down ])
    assert_selector ".column [data-drag-item=card]:first-of-type", text: "Three"
    assert_equal [ "Three", "One", "Two" ], cards("Work")

    focus_card("Two").send_keys([ :alt, :arrow_left ])
    within(".column", text: "To Do", match: :first) { assert_text "Two" }
    assert_equal "Two", focused_text
    assert_equal [ "Three", "One" ], @project.tasks.where(status: statuses(:goal_work)).order(:position).map(&:title)
  end

  test "a column header moves the column with Alt+Left and Alt+Right" do
    visit_board

    find("h2", text: "Work").tap { |h| execute_script("arguments[0].focus()", h) }.send_keys([ :alt, :arrow_left ])

    assert_selector "[data-drag-item=column]:first-of-type h2", text: "Work"
    assert_equal [ "Work", "To Do", "Done" ], all(".column h2").map(&:text)
    assert_equal "Work", focused_text
    assert_equal "Column Work moved to position 1", announcement
    assert_equal [ "Work", "To Do", "Done" ], @project.statuses.reload.map(&:title)
  end
end
