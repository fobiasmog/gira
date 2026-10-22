require "support/call_system_test_case"

# Team calls (spec team-call): the board indicator, joining, microphone and
# camera, and the participants' tiles.
class CallTest < CallSystemTestCase
  setup do
    @project = projects(:goal)
    sign_in_as users(:one)
  end

  test "start a call: the member is in it, and another member sees them in it" do
    open_board
    assert_button "Start call"
    join_call

    within("aside.call-pane") do
      assert_link "Goalner"
      # First call in this browser: microphone and camera are on.
      assert_selector "button[aria-pressed=true]", text: "Microphone"
      assert_selector "button[aria-pressed=true]", text: "Camera"
    end

    as users(:two) do
      open_board
      within(".board-header") do
        assert_button "Join call"
        assert_selector ".call-button__count", text: "1"
        assert_text :all, "In the call: User One"
      end
    end
  end

  test "join a running call: both see and hear each other" do
    open_board
    join_call

    as users(:two) do
      open_board
      join_call
      assert_video_from "User One"
      assert_hears
    end

    assert_video_from "User Two"
    assert_hears
  end

  test "no media server configured: no call control" do
    with_livekit(nil) do
      open_board
      # Two answers from the call endpoint: the first one has been rendered.
      page.document.synchronize(5) do
        answers = evaluate_script("performance.getEntriesByType('resource').filter((e) => e.name.endsWith('/call')).length")
        raise Capybara::ExpectationNotMet, "the call state was not asked" if answers < 2
      end
      within(".board-header") { assert_no_selector ".call-button" }
    end
  end

  test "somebody in the call: Join call with their avatars and number" do
    @project.memberships.create!(user: users(:stranger))
    open_board
    join_call
    as(users(:two)) { open_board; join_call }

    as users(:stranger), session: :third do
      open_board
      within(".board-header") do
        assert_button "Join call"
        assert_selector ".call-button__avatars .avatar", count: 2
        assert_selector ".call-button__count", text: "2"
        assert_text :all, "2 participants"
        assert_text :all, "User One"
        assert_text :all, "User Two"
      end
    end
  end

  test "participants refresh within 30 seconds, without a reload" do
    open_board
    assert_button "Start call"

    as users(:two) do
      open_board
      click_button "Start call"
      assert_selector ".tile", text: "You"
    end

    within(".board-header") { assert_button "Join call", wait: 30 }
    assert_text :all, "In the call: User Two"
  end

  test "member already in the call: In call shows the expanded call" do
    open_board
    join_call
    click_button "Shrink the call"
    assert_no_selector "aside.call-pane"

    within(".side-nav") { click_link "Backlog" }
    assert_selector "h1", text: "Backlog"
    within(".side-nav") { click_link "Board" }

    click_button "In call"
    assert_selector "aside.call-pane"
    assert_no_selector ".call-bar"
  end

  test "turn the camera off: the others see the avatar instead" do
    open_board
    join_call
    as(users(:two)) { open_board; join_call }
    assert_video_from "User Two"

    as(users(:two)) { click_button "Camera" }

    assert_avatar_of "User Two"
    as(users(:two)) { assert_selector "button[aria-pressed=false]", text: "Camera" }
  end

  test "mute: the others see a muted marker" do
    open_board
    join_call
    as(users(:two)) { open_board; join_call }
    within(".tile", text: "User Two") { assert_no_text "Microphone off" }

    as(users(:two)) { click_button "Microphone" }

    within(".tile", text: "User Two") { assert_selector ".tile__muted", text: "Microphone off" }
  end

  test "choice remembered: the next call starts with the camera off and the microphone on" do
    open_board
    join_call
    click_button "Camera"
    assert_selector "button[aria-pressed=false]", text: "Camera"
    click_button "Leave"
    assert_button "Start call"

    join_call

    assert_selector "button[aria-pressed=false]", text: "Camera"
    assert_selector "button[aria-pressed=true]", text: "Microphone"
    assert_avatar_of "You"
  end

  test "camera access refused: in the call without the camera, told why, seeing and hearing the others" do
    open_board
    join_call

    with_media_permissions(users(:two), camera: "denied", microphone: "granted") do
      open_board
      join_call

      assert_text "The browser blocks the camera, so it is off."
      assert_selector "button[aria-pressed=false]", text: "Camera"
      assert_selector "button[aria-pressed=true]", text: "Microphone"
      assert_avatar_of "You"
      assert_video_from "User One"
      assert_hears
    end

    assert_avatar_of "User Two"
  end

  test "own tile: labelled You, with the video mirrored" do
    open_board
    join_call

    assert_video_from "You"
    assert_equal "matrix(-1, 0, 0, 1, 0, 0)", find(".tile", text: "You").find("video").evaluate_script("getComputedStyle(this).transform")
  end

  test "join announced to screen readers" do
    open_board
    join_call

    as(users(:two)) { open_board; join_call }

    assert_selector "[aria-live=polite]", text: "User Two joined the call", visible: :all
  end
end
