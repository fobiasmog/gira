module GoalnerMcp
  # The verified credential of one MCP request (add-mcp-server design.md,
  # decision 6): a personal API token, or the access token of an MCP
  # connection (add-mcp-oauth design.md, decision 9). The SDK hands it to tool
  # handlers as server_context.auth_info.
  #
  # An exception raised in a tool handler never leaves the SDK, which turns it
  # into a JSON-RPC error. So a handler whose API request answers 401 marks the
  # credential rejected, and Authentication answers the whole request with 401.
  class Credential < MCP::Server::OAuth::AccessToken
    attr_reader :cache_key

    # The status of the tool call's API request, for the request log.
    attr_accessor :api_status

    # Where a connection's access token is exchanged for connection tokens.
    attr_reader :connection_tokens

    def initialize(cache_key:, connection_tokens: nil, **attributes)
      super(**attributes)
      @cache_key = cache_key
      @connection_tokens = connection_tokens
      @rejected = false
    end

    # An MCP connection's access token, rather than a personal token.
    def connection?
      !@connection_tokens.nil?
    end

    # Personal tokens carry no scope: the API decides what they may do.
    def read_only_connection?
      connection? && !scope?("write")
    end

    # The bearer value tool calls send the API (UpstreamCredential), worked
    # out once per request: Authentication asks before the transport sees
    # the request, and ToolCall reuses the answer. A rate-limited exchange is
    # remembered too, and raised again to each caller (harden-mcp-oauth
    # design.md, decision 1).
    def upstream_token
      @upstream_token ||= begin
        UpstreamCredential.for(self)
      rescue ConnectionTokens::RateLimited => error
        error
      end
      raise @upstream_token if @upstream_token.is_a?(Exception)

      @upstream_token
    end

    def reject!
      @rejected = true
    end

    def rejected?
      @rejected
    end
  end

  # The bearer value a tool call sends to the API for a verified credential: a
  # personal token is sent as it is, and a connection's access token is
  # exchanged for a connection token (ConnectionTokens). Raises
  # ConnectionTokens::Refused or ::RateLimited when the exchange refuses.
  module UpstreamCredential
    def self.for(auth_info)
      auth_info.connection? ? auth_info.connection_tokens.token_for(auth_info) : auth_info.token
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
