require "test_helper"

class SentryTest < ActiveSupport::TestCase
  test "before_send removes request bodies, cookies, IP addresses and user details" do
    configuration = Sentry::Configuration.new
    configuration.data_collection.user_info = true
    configuration.data_collection.cookies.mode = :deny_list
    configuration.data_collection.http_bodies = [ :incoming_request ]

    event = Sentry::ErrorEvent.new(configuration: configuration)
    event.user = { id: 7, email: "ada@example.com", ip_address: "203.0.113.9" }
    event.rack_env = Rack::MockRequest.env_for("https://goalner.test/api/feedback",
      method: "POST", input: "message=private+text", "CONTENT_TYPE" => "application/x-www-form-urlencoded",
      "HTTP_COOKIE" => "session_id=abc", "REMOTE_ADDR" => "203.0.113.9", "HTTP_X_FORWARDED_FOR" => "203.0.113.9")
    assert event.request.data.present?, "precondition: the unscrubbed event carries a body"

    payload = SentryScrubber.call(event, {}).to_json_compatible.to_s

    assert_equal({ id: 7 }, event.user)
    assert_nil event.request.data
    assert_nil event.request.cookies
    assert_no_match(/private text|private\+text|session_id|abc|203\.0\.113\.9|ada@example/, payload)
  end

  test "Sentry is configured to collect no personal data" do
    data_collection = Sentry.configuration.data_collection

    assert_not data_collection.user_info
    assert_empty data_collection.http_bodies
    assert_equal SentryScrubber, Sentry.configuration.before_send
  end
end
