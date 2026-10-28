require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include ActiveJob::TestHelper

  # SELENIUM_REMOTE_URL points at a browser in another container (local Docker
  # setups); the app server then listens on all interfaces under APP_HOST.
  # Browser console logs are collected so tests can fail on CSP violations.
  capture_console = ->(options) { options.logging_prefs = { browser: "ALL" } }

  if ENV["SELENIUM_REMOTE_URL"]
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ],
      options: { browser: :remote, url: ENV["SELENIUM_REMOTE_URL"] }, &capture_console

    Capybara.server_host = "0.0.0.0"
    Capybara.server_port = 3001
    Capybara.app_host = "http://#{ENV.fetch("APP_HOST")}:3001"

    # The remote driver uploads any typed text that names an existing path. On
    # a case-insensitive filesystem a typed word such as "Docs" names the docs/
    # directory, so only regular files count as uploads.
    setup { page.driver.browser.file_detector = ->((name, *)) { name.to_s if File.file?(name.to_s) } }
  else
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ], &capture_console
  end

  # Icon-only buttons are named by aria-label.
  Capybara.enable_aria_label = true

  # The SPA needs a real build: run `npx vite build --mode test` first. Other
  # tests keep the fixture manifest from config/initializers/vite.rb.
  setup do
    @fixture_manifest_path = Rails.configuration.x.vite.manifest_path
    Rails.configuration.x.vite.manifest_path = Rails.root.join("public/vite/.vite/manifest.json")
  end

  teardown { Rails.configuration.x.vite.manifest_path = @fixture_manifest_path }

  private
    # The last email sent to an address, after delivering queued mail.
    def last_email_to(address)
      perform_enqueued_jobs
      ActionMailer::Base.deliveries.reverse.find { |mail| mail.to.include?(address) }
    end

    # The path of the first link in an email's text part that matches.
    def link_in(mail, pattern)
      URI(mail.text_part.decoded[%r{https?://\S*#{pattern}\S*}]).request_uri
    end

    # A field the SPA marked invalid (after a 422), waiting for the response.
    def assert_invalid_field(label)
      assert_field(label) { |field| field["aria-invalid"] == "true" }
    end

    def sign_in(email_address, password)
      visit new_session_path
      fill_in "Email", with: email_address
      fill_in "Password", with: password
      click_button "Sign in"
      # Wait for the response (an app page, or the form re-rendered at /session)
      # so a following visit cannot overtake the sign-in.
      assert_no_current_path new_session_path
    end
end
