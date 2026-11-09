module GoalnerMcp
  # The protected resource metadata (RFC 9728; spec mcp-server, "Protected
  # resource metadata"; add-mcp-oauth design.md, decision 9): the resource
  # (MCP_RESOURCE_URL), Goalner as its only authorization server (MCP_ISSUER),
  # the scopes, and the Authorization header as the only way to send tokens.
  # Served by the SDK's middleware at the path RFC 9728 derives from the
  # resource, and at the bare well-known path for clients that probe the root.
  class ProtectedResource
    ROOT_PATH = MCP::Server::OAuth::ProtectedResourceMetadata::WELL_KNOWN_PATH_PREFIX
    SCOPES = %w[read write].freeze

    attr_reader :metadata

    def initialize(resource:, issuer:)
      @metadata = MCP::Server::OAuth::ProtectedResourceMetadata.new(
        resource: resource,
        authorization_servers: [ issuer ],
        scopes_supported: SCOPES,
        bearer_methods_supported: [ "header" ]
      )
    end

    # Where 401 answers point: the document under the public origin.
    def url(public_url)
      "#{public_url.chomp("/")}#{metadata.well_known_path}"
    end

    # Rack middleware serving the document at both paths.
    class Middleware
      def initialize(app, metadata)
        @path = metadata.well_known_path
        @served = MCP::Server::OAuth::ProtectedResourceMetadataMiddleware.new(app, metadata)
      end

      def call(env)
        env = env.merge("PATH_INFO" => @path) if env["PATH_INFO"] == ROOT_PATH
        @served.call(env)
      end
    end
  end
end
