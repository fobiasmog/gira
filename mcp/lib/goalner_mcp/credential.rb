module GoalnerMcp
  # The verified credential of one MCP request (add-mcp-server design.md,
  # decision 6). The SDK hands it to tool handlers as server_context.auth_info.
  #
  # An exception raised in a tool handler never leaves the SDK, which turns it
  # into a JSON-RPC error. So a handler whose API request answers 401 marks the
  # credential rejected, and Authentication answers the whole request with 401.
  class Credential < MCP::Server::OAuth::AccessToken
    attr_reader :cache_key

    # The status of the tool call's API request, for the request log.
    attr_accessor :api_status

    def initialize(cache_key:, **attributes)
      super(**attributes)
      @cache_key = cache_key
      @rejected = false
    end

    def reject!
      @rejected = true
    end

    def rejected?
      @rejected
    end
  end

  # The bearer value a tool call sends to the API for a verified credential: a
  # personal token is sent as it is. add-mcp-oauth exchanges connection access
  # tokens here.
  module UpstreamCredential
    def self.for(auth_info)
      auth_info.token
    end
  end

  # The API answered 401 to a tool call: the credential died after the request
  # was authenticated (spec mcp-server, "Token revoked between calls").
  class Unauthorized < StandardError
    def initialize(message = "The API rejected the credential.")
      super
    end
  end
end
