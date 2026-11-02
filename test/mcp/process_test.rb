require "test_helper"
require "capybara"
require "open3"

# The MCP server is a process of its own without database access (spec
# mcp-server, "Isolation from the database"; add-mcp-server design.md,
# decision 2). It loads mcp/config.ru in a fresh Ruby process, without
# DATABASE_URL or RAILS_MASTER_KEY, and lists tools and projects there. The
# API it reaches is this test's Rails application, served over HTTP on a free
# port.
class McpProcessTest < ActiveSupport::TestCase
  SCRIPT = <<~RUBY
    require "bundler/setup"
    require "rack"
    require "json"

    app = Rack::Builder.parse_file("mcp/config.ru")
    responses = [ [ "tools/list", nil ], [ "tools/call", { name: "listProjects", arguments: {} } ] ].map do |method, params|
      response = Rack::MockRequest.new(app).post("/mcp",
        "HTTP_HOST" => "localhost:3100", "CONTENT_TYPE" => "application/json",
        "HTTP_ACCEPT" => "application/json", "HTTP_MCP_PROTOCOL_VERSION" => "2025-11-25",
        "HTTP_AUTHORIZATION" => "Bearer glnr_two_goal_read",
        input: JSON.generate({ jsonrpc: "2.0", id: 1, method: method, params: params }.compact))
      [ response.status, JSON.parse(response.body) ]
    end

    puts JSON.generate(rails: defined?(Rails), active_record: defined?(ActiveRecord), responses: responses)
  RUBY

  test "started without a database: tools and the token's project, through the API" do
    Capybara.server = :puma, { Silent: true }
    api = Capybara::Server.new(Rails.application).boot

    env = { "DATABASE_URL" => nil, "RAILS_MASTER_KEY" => nil, "RAILS_ENV" => nil, "RACK_ENV" => "development",
            "GOALNER_API_URL" => "http://#{api.host}:#{api.port}" }
    output, errors, status = Open3.capture3(env, RbConfig.ruby, "-e", SCRIPT, chdir: Rails.root.to_s)
    assert status.success?, errors

    result = JSON.parse(output.lines.last)
    assert_nil result["rails"]
    assert_nil result["active_record"]

    (list_status, list), (call_status, call) = result["responses"]
    assert_equal 200, list_status, list
    assert_not_empty list.dig("result", "tools")
    assert_equal 200, call_status, call
    projects = JSON.parse(call.dig("result", "content", 0, "text"))
    assert_equal [ projects(:goal).id ], projects.map { it["id"] }
  end
end
