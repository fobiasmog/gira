# The MCP server (spec mcp-server; add-mcp-server design.md). A Rack
# application that offers the token API as MCP tools and reaches Goalner only
# through that API: it never boots Rails and has no database access
# (decision 2). bin/mcp serves it with Puma.
require "bundler/setup"
Bundler.require(:mcp)
require "digest"
require "json"
require "logger"
require "net/http"
require "rack"
require "securerandom"
require "sentry-ruby"
require "uri"
require "yaml"

require_relative "goalner_mcp/version"
require_relative "goalner_mcp/api_client"
require_relative "goalner_mcp/lru_cache"
require_relative "goalner_mcp/credential"
require_relative "goalner_mcp/token_verifier"
require_relative "goalner_mcp/connection_tokens"
require_relative "goalner_mcp/scoped_server"
require_relative "goalner_mcp/protected_resource"
require_relative "goalner_mcp/jwt_verifier"
require_relative "goalner_mcp/authentication"
require_relative "goalner_mcp/tool_call"
require_relative "goalner_mcp/tool_builder"
require_relative "goalner_mcp/request_log"

module GoalnerMcp
  # Sent to clients on initialize and discover (decision 10).
  INSTRUCTIONS = <<~TEXT.freeze
    Goalner is a task tracker; start with listProjects. Task ids also accept
    keys such as GOAL-12. A read-only token cannot use tools that change data.
  TEXT

  # Browser origins the MCP Inspector uses in development (decision 3).
  INSPECTOR_ORIGINS = %w[ http://localhost:6274 http://127.0.0.1:6274 ].freeze

  # Raised for what clients did wrong, such as calling an unknown tool, and
  # handed to the SDK's exception reporter all the same. Not reported.
  EXPECTED_ERRORS = [ MCP::Server::RequestHandlerError, MCP::Server::OAuth::Error, Unauthorized ].freeze

  # Matches SentryScrubber in the main application: no request data, headers
  # or environment, and no user (decision 9).
  SENTRY_SCRUBBER = lambda do |event, _hint|
    if (request = event.request)
      request.data = nil
      request.cookies = nil
      request.query_string = nil
      request.headers = {}
      request.env = {}
    end
    event.user = {}
    event.extra = {}
    event
  end

  class << self
    attr_writer :logger

    def logger
      @logger ||= Logger.new($stdout)
    end

    def env
      ENV.fetch("RACK_ENV") { ENV.fetch("RAILS_ENV", "development") }
    end

    def production?
      env == "production"
    end

    # Error reports go to Sentry when SENTRY_DSN is set. The MCP process
    # cannot read the Rails credentials, so the DSN comes from the environment.
    def start_sentry(dsn = ENV["SENTRY_DSN"])
      return if dsn.to_s.empty?

      Sentry.init do |config|
        config.dsn = dsn
        configure_sentry(config)
      end
    end

    def configure_sentry(config)
      config.environment = env
      config.data_collection.user_info = false
      config.data_collection.cookies.mode = :off
      config.data_collection.http_bodies = []
      config.data_collection.stack_frame_variables = false
      config.before_send = SENTRY_SCRUBBER
    end

    # Reports an unexpected exception. The SDK's context, which holds the
    # request body, is never sent.
    def report(exception)
      Sentry.capture_exception(exception) if Sentry.initialized?
    end

    CONNECTION_TOKEN_CACHE_SIZE = 10_000

    def connection_token_cache(redis_url)
      redis_url ? RedisCache.new(redis_url) : LruCache.new(max_size: CONNECTION_TOKEN_CACHE_SIZE, ttl: 3600)
    end

    # A setting from the environment. Development and test fall back to
    # bin/dev's addresses; production refuses to start without it.
    def setting(name, fallback)
      ENV.fetch(name) { production? ? raise(KeyError, "#{name} must be set") : fallback }
    end

    # The Rack application: the Streamable HTTP transport at /mcp, stateless
    # and answering with JSON (decision 3). Requests from a browser origin other
    # than public_url's are refused with 403 (spec "Browser origins"). Only POST
    # is authenticated and reaches the transport: in stateless mode the
    # transport answers a DELETE with 200, where the spec ("MCP endpoint")
    # wants 405 for anything else.
    #
    # The protected resource metadata is served from the origin's well-known
    # paths, and MCP connections' access tokens are verified with the public
    # keys, when given, and exchanged for connection tokens with the service
    # key, cached in Redis or, without REDIS_URL outside production, in memory
    # (add-mcp-oauth design.md, decisions 9 and 11). Production refuses to
    # start without any of these settings.
    def app(
      public_url: setting("MCP_PUBLIC_URL", "http://localhost:3100"),
      api: ApiClient.new(ApiClient::HttpTransport.new(setting("GOALNER_API_URL", "http://localhost:3000"))),
      tools: ToolBuilder.new(api).tools,
      resource: setting("MCP_RESOURCE_URL", "http://localhost:3100/mcp"),
      issuer: setting("MCP_ISSUER", "http://localhost:3000"),
      jwt_public_keys: setting("MCP_JWT_PUBLIC_KEYS", nil),
      service_key: setting("MCP_SERVICE_KEY", "development-mcp-service-key"),
      connection_token_cache: connection_token_cache(setting("REDIS_URL", nil))
    )
      reporter = ->(exception, _context) { report(exception) unless EXPECTED_ERRORS.any? { exception.is_a?(it) } }
      server = ScopedServer.new(name: "goalner", title: "Goalner", version: VERSION, instructions: INSTRUCTIONS, tools: tools,
        configuration: MCP::Configuration.new(exception_reporter: reporter))
      origin = URI(public_url)
      port = ":#{origin.port}" unless origin.port == origin.default_port
      transport = MCP::Server::Transports::StreamableHTTPTransport.new(
        server,
        stateless: true,
        enable_json_response: true,
        serve_subscriptions_listen: false,
        allowed_hosts: [ origin.host ],
        allowed_origins: [ "#{origin.scheme}://#{origin.host}#{port}" ] + (production? ? [] : INSPECTOR_ORIGINS)
      )

      protected_resource = ProtectedResource.new(resource: resource, issuer: issuer)
      verifiers = [ TokenVerifier.new(api) ]
      if jwt_public_keys
        connection_tokens = ConnectionTokens.new(api, service_key: service_key, cache: connection_token_cache)
        verifiers << JwtVerifier.new(metadata: protected_resource.metadata, public_keys: jwt_public_keys, connection_tokens: connection_tokens)
      end
      authenticated = Authentication.new(transport, verifiers: verifiers, resource_metadata_url: protected_resource.url(public_url))
      post_only = ->(env) { env["REQUEST_METHOD"] == "POST" ? authenticated.call(env) : [ 405, { "allow" => "POST" }, [] ] }

      tool_names = tools.map(&:name_value)

      Rack::Builder.app do
        use ProtectedResource::Middleware, protected_resource.metadata
        map("/mcp") do
          use RequestLog, tool_names: tool_names
          run post_only
        end
      end
    end
  end
end
