require "support/call_system_test_case"

# How a call ends without the member leaving it (spec team-call): losing
# access, joining elsewhere, and a media server that cannot be reached.
class CallAccessTest < CallSystemTestCase
  setup do
    @project = projects(:goal)
    sign_in_as users(:one)
    open_board
    join_call
  end

  test "removed during a call: out of the call, told why, and gone for the others" do
    as(users(:two)) { open_board; join_call }
    assert_selector ".tile", text: "User Two"

    @project.remove_member!(users(:two))
    perform_enqueued_jobs

    as users(:two) do
      assert_text "You left the call because you no longer have access to the project."
      assert_no_selector "aside.call-pane"
    end
    assert_no_selector ".tile", text: "User Two"
    assert_in_call @project, users(:one)
  end

  test "project archived during a call: the call ends for every participant" do
    as(users(:two)) { open_board; join_call }

    @project.archive!
    perform_enqueued_jobs

    assert_text "You left the call because you no longer have access to the project."
    assert_no_selector "aside.call-pane"
    as(users(:two)) { assert_no_selector "aside.call-pane" }
    assert_in_call @project
  end

  test "join from a second tab: the first tab leaves and says the call continues elsewhere" do
    as(users(:one)) do
      open_board
      join_call
    end

    assert_text "The call continues in another tab or device."
    assert_no_selector "aside.call-pane"
    as(users(:one)) { assert_selector ".tile", text: "You" }
    assert_in_call @project, users(:one)
  end

  test "media server unreachable: a short message, and not in a call" do
    click_button "Leave"

    with_livekit(url: "ws://localhost:7999", api_key: "devkey", api_secret: "secret") do
      open_board
      click_button "Start call"

      assert_text "Could not connect to the call. Try again later.", wait: 30
      assert_no_selector "aside.call-pane"
      assert_button "Start call"
    end
  end
end
