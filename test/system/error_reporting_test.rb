require "application_system_test_case"
require "support/sentry_capture"

# Spec web-client, "Privacy-preserving error reporting". Runs against the
# production Vite build; the DSN points at this test server.
class ErrorReportingTest < ApplicationSystemTestCase
  SECRETS = [ "Top secret title", "Secret description", "secret@example.com" ].freeze

  setup do
    Rails.application.reload_routes_unless_loaded
    routes = Rails.application.routes
    routes.disable_clear_and_finalize = true
    routes.draw { post "sentry/api/:project_id/envelope", to: SentryCapture::EnvelopesController.action(:create) }
    routes.disable_clear_and_finalize = false
    SentryCapture.events
  end

  teardown do
    SentryCapture.dsn = nil
    Rails.application.reload_routes!
  end

  test "an error in a component is reported with the stack trace and user id, and none of the task's text" do
    user = users(:one)
    sign_in user.email_address, "correct horse battery"
    SentryCapture.dsn = "#{server_origin.sub("://", "://publickey@")}/sentry/1"

    visit "/app/__fixtures/sentry?user_id=#{user.id}"
    click_button "Show the task"

    event = wait_for_event
    exception = event.dig("exception", "values", 0)
    assert_match(/TaskView failed to render/, exception["value"])
    assert_not_empty exception.dig("stacktrace", "frames")
    assert_equal({ "id" => user.id.to_s }, event["user"])

    json = event.to_json
    SECRETS.each { |secret| assert_not_includes json, secret }
    assert_not_includes json, user.email_address
  end

  private
    def server_origin
      Capybara.app_host || "http://#{Capybara.current_session.server.host}:#{Capybara.current_session.server.port}"
    end

    def wait_for_event
      events = []
      Timeout.timeout(10) do
        events.concat(SentryCapture.events) while events.empty? && sleep(0.1)
      end
      events.first
    end
end
