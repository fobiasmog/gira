require "application_system_test_case"
require "support/live_kit_test_helper"

# Base for system tests of calls (spec team-call). They need a LiveKit server
# in development mode at config.x.livekit (`make livekit` or bin/dev locally,
# a pinned binary in CI). Chrome gets a fake camera and microphone and grants
# them without asking, so media really goes through LiveKit. Every browser a
# test used must end without CSP violations, and every call room ends empty.
class CallSystemTestCase < ApplicationSystemTestCase
  include LiveKitTestHelper

  PASSWORD = "correct horse battery"

  fake_media = lambda do |options|
    options.logging_prefs = { browser: "ALL" }
    options.add_argument("--use-fake-ui-for-media-stream")
    options.add_argument("--use-fake-device-for-media-stream")
    # Behind a remote browser the app's origin is not localhost, and only
    # secure contexts may use the camera and microphone.
    options.add_argument("--unsafely-treat-insecure-origin-as-secure=#{Capybara.app_host}") if ENV["SELENIUM_REMOTE_URL"]
  end

  # A driver of its own name, so the other system tests keep theirs.
  if ENV["SELENIUM_REMOTE_URL"]
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ],
      options: { name: :call_chrome, browser: :remote, url: ENV["SELENIUM_REMOTE_URL"] }, &fake_media
  else
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ], options: { name: :call_chrome }, &fake_media
  end

  # A browser without the fake permission prompt, which would grant every
  # request: tests set each permission through the DevTools Protocol instead
  # (with_media_permissions).
  ASKING_DRIVER = :call_chrome_asking
  Capybara.register_driver ASKING_DRIVER do |app|
    options = Selenium::WebDriver::Chrome::Options.new(args: %w[--headless=new --window-size=1400,1000 --use-fake-device-for-media-stream])
    options.logging_prefs = { browser: "ALL" }
    if ENV["SELENIUM_REMOTE_URL"]
      options.add_argument("--unsafely-treat-insecure-origin-as-secure=#{Capybara.app_host}")
      Capybara::Selenium::Driver.new(app, browser: :remote, url: ENV["SELENIUM_REMOTE_URL"], options: options)
    else
      Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
    end
  end

  setup do
    @sessions = [ Capybara.session_name ]
    assert media_server_running?, "LiveKit is not running at #{Rails.configuration.x.livekit[:url]}: start it with `make livekit`"
    close_calls
  end

  teardown do
    @sessions.uniq.each do |name|
      using_session(name) do
        violations = page.driver.browser.logs.get(:browser).map(&:message).grep(/Content Security Policy|\Asecurity/)
        assert_empty violations, "CSP violations in the console of the #{name} browser"
      end
    end
    close_calls
  end

  private
    def sign_in_as(user)
      sign_in user.email_address, PASSWORD
    end

    def open_board(project = projects(:goal), layout: "board")
      visit "/app/projects/#{project.id}/#{layout}"
      assert_selector "h1", text: project.title
    end

    # Starts or joins the call from the board header, and waits until the
    # connection is up. The participant lists the server cached for 5 seconds
    # are dropped (the app server shares this process's cache), so other
    # boards show the change on their next poll.
    def join_call
      find(:button, text: /\A(Start call|Join call)/).click
      assert_button "In call"
      assert_no_text "Connecting…"
      assert_selector ".tile", text: "You"
      Rails.cache.clear
    end

    # Runs the block in another browser, signed in as the given member. Every
    # session keeps its browser for the whole run, so tests share a few names.
    def as(user, session: :second)
      using_session(session) do
        unless @sessions.include?(session)
          @sessions << session
          sign_in_as user
        end
        yield
      end
    end

    # A participant's tile, shown with live video from their camera. A video
    # with a width proves that media reached this browser through LiveKit.
    def assert_video_from(name)
      tile = find(".tile", text: name)
      page.document.synchronize(15) do
        width = tile.find("video", visible: :all).evaluate_script("this.videoWidth")
        raise Capybara::ExpectationNotMet, "no video from #{name}" unless width.to_i.positive? && tile.has_css?("video", visible: true, wait: 0)
      end
    end

    def assert_avatar_of(name)
      within(".tile", text: name) do
        assert_no_selector "video", visible: true
        assert_selector ".avatar"
      end
    end

    # The other participants' sound is playing in this browser.
    def assert_hears(count = 1)
      assert_selector "audio[data-track]", count: count, visible: :all, wait: 10
      page.document.synchronize(10) do
        playing = evaluate_script(<<~JS)
          [...document.querySelectorAll("audio[data-track]")].every((audio) =>
            !audio.paused && audio.srcObject?.getAudioTracks().some((track) => track.readyState === "live"))
        JS
        raise Capybara::ExpectationNotMet, "the call's sound is not playing" unless playing
      end
    end

    # Who LiveKit itself says is in a project's call.
    def assert_in_call(project, *users)
      page.document.synchronize(10) do
        Rails.cache.clear
        names = ProjectCall.new(project).participants.map(&:name).sort
        raise Capybara::ExpectationNotMet, "in the call: #{names}" unless names == users.map(&:name).sort
      end
    end

    # Records every camera and microphone track the page gets from now on.
    def record_media_tracks
      execute_script(<<~JS)
        window.__mediaTracks = []
        const getUserMedia = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices)
        navigator.mediaDevices.getUserMedia = async (constraints) => {
          const stream = await getUserMedia(constraints)
          window.__mediaTracks.push(...stream.getTracks())
          return stream
        }
      JS
    end

    # The camera and microphone the page used are stopped.
    def assert_media_released
      page.document.synchronize(5) do
        released = evaluate_script("window.__mediaTracks.length > 0 && window.__mediaTracks.every((track) => track.readyState === 'ended')")
        raise Capybara::ExpectationNotMet, "the camera or microphone is still on" unless released
      end
    end

    def on_narrow_screen
      page.driver.browser.manage.window.resize_to(390, 844)
      yield
    ensure
      page.driver.browser.manage.window.resize_to(1400, 1000)
    end

    def pane_width
      evaluate_script("document.querySelector('.call-pane').getBoundingClientRect().width").round
    end

    # Runs the block in another browser, as a member whose browser grants or
    # refuses the camera and microphone as given ("granted" or "denied").
    def with_media_permissions(user, camera:, microphone:)
      Capybara.using_driver(ASKING_DRIVER) do
        sign_in_as user
        { camera: camera, microphone: microphone }.each do |name, setting|
          execute_cdp("Browser.setPermission", permission: { name: name }, setting: setting, origin: Capybara.app_host)
        end
        yield
        violations = page.driver.browser.logs.get(:browser).map(&:message).grep(/Content Security Policy|\Asecurity/)
        assert_empty violations, "CSP violations in the console"
      end
    end

    # Other settings change the Content Security Policy. Every request gets the
    # same SPA page in tests, so revisiting a page would be a 304 that keeps
    # the policy cached under the other settings: the browser cache goes too.
    def with_livekit(settings)
      execute_cdp("Network.clearBrowserCache")
      super
    ensure
      execute_cdp("Network.clearBrowserCache")
    end

    def media_server_running?
      Net::HTTP.get_response(URI(Rails.configuration.x.livekit[:url].sub(/\Aws/, "http"))).is_a?(Net::HTTPSuccess)
    rescue SystemCallError, IOError, SocketError
      false
    end

    # Rooms are named after project ids, which fixtures keep between tests.
    def close_calls
      Project.find_each { |project| ProjectCall.new(project).close }
    rescue LiveKit::RoomService::Error
      nil
    end
end
