require "support/call_system_test_case"

# A call lasts until the member leaves (spec team-call): it stays on every
# screen of the client, and leaving or reloading ends it.
class CallNavigationTest < CallSystemTestCase
  setup do
    @project = projects(:goal)
    @other = projects(:side)
    @other.memberships.create!(user: users(:one))
    sign_in_as users(:one)
  end

  test "open a task during a call: the task page is shown and the member is still in the call" do
    task = @project.tasks.create!(title: "Write the spec", creator: users(:one), status: statuses(:goal_todo))
    open_board
    join_call

    click_link "Write the spec"

    assert_selector "h1", text: "Write the spec"
    assert_current_path "/app/projects/#{@project.id}/tasks/#{task.key}"
    within("aside.call-pane") { assert_video_from "You" }
    assert_in_call @project, users(:one)
  end

  test "another project during a call: still in the call, which names its project and links to its board" do
    open_board
    join_call

    within(".side-nav") { click_link "Side project" }

    assert_selector "h1", text: "Side project"
    within(".board-header") { assert_button "Start call" }
    within("aside.call-pane") do
      assert_selector ".tile", text: "You"
      click_link "Goalner"
    end
    assert_current_path "/app/projects/#{@project.id}/board"
    assert_button "In call"
    assert_in_call @project, users(:one)
  end

  test "switch to another project's call after confirming; cancelling stays" do
    open_board
    join_call
    within(".side-nav") { click_link "Side project" }
    assert_selector "h1", text: "Side project"

    click_button "Start call"
    within("dialog[open]") do
      assert_text "You are in the call of “Goalner”. Leave it and join the call of “Side project”?"
      click_button "Cancel"
    end
    assert_selector "aside.call-pane", text: "Goalner"
    assert_in_call @project, users(:one)

    click_button "Start call"
    within("dialog[open]") { click_button "Leave and join" }

    assert_button "In call"
    within("aside.call-pane") do
      assert_link "Side project"
      assert_selector ".tile", text: "You"
    end
    assert_in_call @other, users(:one)
    assert_in_call @project
  end

  test "leave: the call view closes, the camera and microphone stop, and the others no longer see the member" do
    open_board
    record_media_tracks
    join_call
    as(users(:two)) { open_board; join_call; assert_selector ".tile", text: "User One" }

    click_button "Leave"

    assert_no_selector "aside.call-pane"
    assert_no_selector ".call-bar"
    assert_media_released
    within(".board-header") { assert_button "Join call" }
    as(users(:two)) { assert_no_selector ".tile", text: "User One" }
    assert_in_call @project, users(:two)
  end

  test "reload during a call: not in the call afterwards, and nothing joins again" do
    open_board
    join_call

    visit current_url

    assert_selector "h1", text: "Goalner"
    assert_in_call @project
    within(".board-header") { assert_button "Start call" }
    assert_no_selector "aside.call-pane"
    loaded = evaluate_script("performance.getEntriesByType('resource').some((entry) => entry.name.includes('livekit-client'))")
    assert_not loaded, "the call library is not even loaded, so the camera and microphone stay off"
  end
end
