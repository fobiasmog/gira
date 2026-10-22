require "test_helper"
require "support/production_probe"
require "support/live_kit_test_helper"

class SecurityHeadersTest < ActionDispatch::IntegrationTest
  include LiveKitTestHelper

  POLICY = "default-src 'self'; script-src 'self'; style-src 'self'; font-src 'self'; " \
    "img-src 'self' data: blob:; connect-src 'self'; frame-src 'self'; form-action 'self'; " \
    "object-src 'none'; base-uri 'self'; frame-ancestors 'none'"

  test "HTML responses carry the strict content security policy" do
    with_livekit(nil) { get rails_health_check_path }

    assert_equal POLICY, response.headers["Content-Security-Policy"]
  end

  test "the configured media server's WebSocket and HTTP addresses are allowed connections" do
    with_livekit(url: "wss://media.example.com", api_key: "key", api_secret: "secret") { get rails_health_check_path }

    assert_equal POLICY.sub("connect-src 'self'", "connect-src 'self' wss://media.example.com https://media.example.com"),
      response.headers["Content-Security-Policy"]
  end

  test "a media server on another port keeps the port in both addresses" do
    with_livekit(url: "ws://localhost:7880", api_key: "devkey", api_secret: "secret") { get rails_health_check_path }

    assert_includes response.headers["Content-Security-Policy"], "connect-src 'self' ws://localhost:7880 http://localhost:7880;"
  end

  test "HTML responses carry the browser hardening headers" do
    get rails_health_check_path

    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "strict-origin-when-cross-origin", response.headers["Referrer-Policy"]
    assert_equal "camera=(self), microphone=(self), geolocation=(), payment=(), usb=()",
      response.headers["Permissions-Policy"]
  end

  test "logs filter credentials, emails and user-written bodies" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    params = { password: "p", email_address: "a@b.c", token: "t", body: "b", description: "d", message: "m", title: "kept" }

    assert_equal({ password: "[FILTERED]", email_address: "[FILTERED]", token: "[FILTERED]", body: "[FILTERED]",
                   description: "[FILTERED]", message: "[FILTERED]", title: "kept" }, filter.filter(params))
  end

  test "production redirects HTTP to HTTPS and sends HSTS and the production policy" do
    http, https = ProductionProbe.request({ url: "http://goalner.test/up" }, { url: "https://goalner.test/up" })

    assert_equal 301, http["status"]
    assert_equal "https://goalner.test/up", http["headers"]["location"]

    assert_equal 200, https["status"]
    hsts = https["headers"]["strict-transport-security"]
    assert_operator hsts[/max-age=(\d+)/, 1].to_i, :>=, 365.days.to_i
    assert_includes hsts, "includeSubDomains"
    csp = https["headers"]["content-security-policy"]
    assert_includes csp, "script-src 'self';"
    assert_includes csp, "frame-ancestors 'none'"
    assert_no_match(/unsafe-inline|unsafe-eval|localhost|127\.0\.0\.1/, csp)
    # No media server in the (absent) credentials: no call destination either.
    assert_includes csp, "connect-src 'self';"
  end
end
