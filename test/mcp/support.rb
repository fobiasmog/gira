require "test_helper"
require "rack/test"
require_relative "../../mcp/lib/goalner_mcp"

# Base of the MCP server tests (add-mcp-server design.md, decision 7). The MCP
# Rack application runs under Rack::Test, and its API client calls the Rails
# application in-process instead of over the network, so tests exercise the
# real API, with fixtures and token rules.
class McpIntegrationTest < ActiveSupport::TestCase
  include Rack::Test::Methods

  # Rack::Test's default host, as the public origin, so requests pass the
  # transport's Host check.
  PUBLIC_URL = "http://example.org"

  # Stands in for ApiClient::HttpTransport: hands each request to the Rails
  # application and records it, so tests can count API requests.
  class RackTransport
    attr_reader :requests

    def initialize(app)
      @app = app
      @requests = []
    end

    def call(method, path, headers, body)
      @requests << "#{method} #{path}"
      env = headers.to_h { |name, value| [ name == "Content-Type" ? "CONTENT_TYPE" : "HTTP_#{name.upcase.tr("-", "_")}", value ] }
      response = Rack::MockRequest.new(@app).request(method, path, env.merge(input: body.to_s))
      [ response.status, response.body ]
    end
  end

  # Keeps test output clean; logging tests swap in their own logger.
  GoalnerMcp.logger = Logger.new(IO::NULL)

  setup do
    @api_transport = RackTransport.new(Rails.application)
  end

  def app
    @app ||= build_app
  end

  # The MCP application as configured in production: the resource, the
  # issuer and the public key match this Rails application's (Oauth).
  def build_app(public_url: PUBLIC_URL, **options)
    GoalnerMcp.app(public_url: public_url, api: GoalnerMcp::ApiClient.new(@api_transport), resource: Oauth.resource,
      issuer: Oauth.issuer, jwt_public_keys: Oauth::JwtGenerator.public_key_pem, **options)
  end

  # Sends one JSON-RPC request the way a stateless 2025-11-25 client does,
  # with no initialize first, and returns the Rack::Test response.
  def mcp_request(method, params = nil, token: default_token, headers: {})
    env = { "CONTENT_TYPE" => "application/json", "HTTP_ACCEPT" => "application/json, text/event-stream",
            "HTTP_MCP_PROTOCOL_VERSION" => "2025-11-25" }
    env["HTTP_AUTHORIZATION"] = "Bearer #{token}" if token
    post "/mcp", JSON.generate({ jsonrpc: "2.0", id: 1, method: method, params: params }.compact), env.merge(headers)
    last_response
  end

  # The JSON-RPC result of a successful request.
  def mcp_result(...)
    response = mcp_request(...)
    assert_equal 200, response.status, response.body
    JSON.parse(response.body).fetch("result")
  end

  def api_requests
    @api_transport.requests
  end

  # The parameters of a response's Bearer challenge, in whatever order the
  # header lists them.
  def challenge_parameters(response)
    header = response.headers["www-authenticate"].to_s
    assert_match(/\ABearer\b/, header)
    header.delete_prefix("Bearer").scan(/(\w+)="((?:[^"\\]|\\.)*)"/).to_h
  end

  # The token requests carry unless a test names one.
  def default_token
    nil
  end
end
