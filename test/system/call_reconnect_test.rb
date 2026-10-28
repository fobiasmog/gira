require "support/call_system_test_case"

# Connection problems (spec team-call). The connection is interrupted with
# LiveKit's own simulation, which test builds expose as simulateCallScenario:
# it closes the signalling connection as a network drop would, and DevTools'
# offline mode leaves that WebSocket open.
class CallReconnectTest < CallSystemTestCase
  TOKEN_TTL = 2.seconds

  setup do
    @project = projects(:goal)
    sign_in_as users(:one)
  end

  test "short interruption: the call shows that it is reconnecting, and is back without the member acting" do
    open_board
    join_call
    as(users(:two)) { open_board; join_call }
    # LiveKit shows the state while it resumes, which can take only a moment.
    execute_script(<<~JS)
      window.__sawReconnecting = false
      new MutationObserver(() => { window.__sawReconnecting ||= document.body.textContent.includes("Reconnecting…") })
        .observe(document.body, { subtree: true, childList: true, characterData: true })
    JS

    interrupt_connection(3.seconds)

    page.document.synchronize(15) do
      raise Capybara::ExpectationNotMet, "Reconnecting… never shown" unless evaluate_script("window.__sawReconnecting")
    end
    assert_no_text "Reconnecting…", wait: 15
    assert_no_text "The call was disconnected."
    assert_video_from "User Two"
    as(users(:two)) { assert_video_from "User One" }
    assert_in_call @project, users(:one), users(:two)
  end

  # LiveKit hands connected participants refreshed tokens, and the client must
  # reconnect with those (team-call design.md, "Risks / Trade-offs"). LiveKit
  # checks expiry against its own clock, with a minute of leeway, so the test
  # waits until LiveKit refuses the original token instead of travelling in time.
  test "reconnects after the original token has expired" do
    with_livekit(Rails.configuration.x.livekit.merge(token_ttl: TOKEN_TTL)) do
      open_board
      join_call
      # Issued no later than now, so it expires no later than this.
      expires_at = TOKEN_TTL.from_now
      as(users(:two)) { open_board; join_call }

      wait_until_media_server_refuses_tokens_expiring(expires_at)

      # Resuming the signalling connection, then joining the room again.
      interrupt_connection(1.second)
      assert_no_text "Reconnecting…", wait: 15
      execute_script("simulateCallScenario('full-reconnect')")
      assert_no_text "Reconnecting…", wait: 15

      assert_no_text "The call was disconnected."
      assert_selector "aside.call-pane"
      assert_video_from "User Two"
      as(users(:two)) { assert_video_from "User One" }
      assert_in_call @project, users(:one), users(:two)
    end
  end

  private
    def interrupt_connection(duration)
      execute_script("simulateCallScenario('signal-reconnect', #{duration.in_milliseconds})")
    end

    def wait_until_media_server_refuses_tokens_expiring(expires_at)
      settings = Rails.configuration.x.livekit
      token = LiveKit::AccessToken.new(api_key: settings[:api_key], api_secret: settings[:api_secret], identity: "probe",
        video: { roomJoin: true, room: "probe" }, ttl: TOKEN_TTL).to_jwt(now: expires_at - TOKEN_TTL)
      validate = URI("#{settings[:url].sub(/\Aws/, "http")}/rtc/validate?room=probe&access_token=#{token}")

      Timeout.timeout(90) do
        sleep 1 until Net::HTTP.get_response(validate).code == "401"
      end
    end
end
