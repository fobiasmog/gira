require_relative "support"
require "sentry/test_helper"

# What the MCP server logs and reports (spec mcp-server, "Privacy of MCP
# logs"; add-mcp-server design.md, decision 9).
class McpLoggingTest < McpIntegrationTest
  include Sentry::TestHelper

  # The test client keeps the application's configuration: requests through
  # the Rails application carry the client over to later tests, which check
  # that configuration. GoalnerMcp.configure_sentry is checked on its own.
  setup do
    @log = StringIO.new
    @logger = GoalnerMcp.logger
    GoalnerMcp.logger = Logger.new(@log)
    setup_sentry_test
  end

  teardown do
    GoalnerMcp.logger = @logger
    teardown_sentry_test
  end

  def create_task(title)
    mcp_request("tools/call", { name: "createTask", arguments: { project_id: projects(:goal).id, title: title } }, token: "glnr_two_goal_read_write")
  end

  test "logged tool call" do
    create_task("Quarterly plan")

    line = @log.string.lines.sole
    assert_match(/ mcp request_id=[\w-]+ method=tools\/call tool=createTask api_status=201 result=ok duration_ms=[\d.]+$/, line)
    assert_no_match(/glnr_|Quarterly plan|two_goal/, @log.string)
  end

  test "lists, tool errors, refusals and unknown tools each get one line" do
    mcp_request("tools/list", token: "glnr_two_goal_read")
    mcp_request("tools/call", { name: "createTask", arguments: { project_id: projects(:goal).id, title: "Quarterly plan" } }, token: "glnr_two_goal_read")
    mcp_request("tools/list")
    mcp_request("tools/call", { name: "Quarterly plan", arguments: {} }, token: "glnr_two_goal_read")

    lines = @log.string.lines
    assert_equal 4, lines.size
    assert_match(/method=tools\/list tool=- api_status=- result=ok/, lines[0])
    assert_match(/method=tools\/call tool=createTask api_status=403 result=tool_error/, lines[1])
    assert_match(/method=tools\/list tool=- api_status=- result=unauthorized/, lines[2])
    assert_match(/method=tools\/call tool=unknown api_status=- result=error/, lines[3])
    assert_no_match(/glnr_|Quarterly plan/, @log.string)
  end

  test "the request id comes from the proxy when it sends a plain one" do
    mcp_request("tools/list", token: "glnr_two_goal_read", headers: { "HTTP_X_REQUEST_ID" => "abc-123" })
    mcp_request("tools/list", token: "glnr_two_goal_read", headers: { "HTTP_X_REQUEST_ID" => "abc 123\nforged=1" })

    first, second = @log.string.lines
    assert_includes first, "request_id=abc-123 "
    assert_no_match(/forged|abc 123/, second)
  end

  test "an exception in a tool is reported without request data, headers or arguments" do
    failing = MCP::Tool.define(name: "failing", input_schema: { type: "object", properties: { title: { type: "string" } } }) do |server_context:, **|
      raise "Tool failed"
    end
    @app = GoalnerMcp.app(public_url: PUBLIC_URL, api: GoalnerMcp::ApiClient.new(@api_transport), tools: [ failing ])

    mcp_request("tools/call", { name: "failing", arguments: { title: "Quarterly plan" } }, token: "glnr_two_goal_read")

    event = sentry_events.sole
    assert_match(/\ATool failed\b/, event.exception.values.sole.value)
    assert_nil event.request
    # The stack frames quote source lines, this test's included.
    payload = event.to_json_compatible.tap { |data| data["exception"]["values"].each { it.delete("stacktrace") } }
    assert_no_match(/Quarterly plan|glnr_|Authorization/i, payload.to_s)
  end

  test "an exception outside the SDK is reported and answered with a generic 500" do
    log = GoalnerMcp::RequestLog.new(->(_env) { raise "Broken middleware" }, tool_names: [])

    status, _headers, body = log.call(Rack::MockRequest.env_for("/mcp", method: "POST", input: "{}",
      "HTTP_AUTHORIZATION" => "Bearer glnr_two_goal_read"))

    assert_equal 500, status
    assert_not_includes body.join, "Broken"
    assert_match(/\ABroken middleware\b/, sentry_events.sole.exception.values.sole.value)
    assert_match(/result=error/, @log.string)
  end

  test "the MCP process configures Sentry to collect no personal data" do
    config = Sentry::Configuration.new
    GoalnerMcp.configure_sentry(config)

    assert_not config.data_collection.user_info
    assert_empty config.data_collection.http_bodies
    assert_equal GoalnerMcp::SENTRY_SCRUBBER, config.before_send
  end

  test "the scrubber drops request data, headers and the environment" do
    event = Sentry::ErrorEvent.new(configuration: Sentry.configuration)
    event.rack_env = Rack::MockRequest.env_for("https://goalner.test/mcp?token=glnr_secret", method: "POST",
      input: '{"params":{"arguments":{"title":"Quarterly plan"}}}', "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer glnr_secret")

    payload = GoalnerMcp::SENTRY_SCRUBBER.call(event, {}).to_json_compatible.to_s

    assert_no_match(/glnr_secret|Quarterly plan|Authorization/, payload)
  end

  test "client errors are not reported" do
    mcp_request("tools/call", { name: "noSuchTool", arguments: {} }, token: "glnr_two_goal_read")
    mcp_request("tools/call", { name: "createTask", arguments: {} }, token: "glnr_two_goal_read")

    assert_empty sentry_events
  end
end
