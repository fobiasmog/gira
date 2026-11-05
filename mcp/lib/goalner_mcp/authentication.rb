module GoalnerMcp
  # Authenticates every MCP request before the transport sees it (spec
  # mcp-server, "Authentication"; add-mcp-server design.md, decision 6).
  #
  # - Only the Authorization header counts: a token in the query string or the
  #   body never authenticates. No header, another scheme, or a malformed
  #   Bearer value gets 401 with a Bearer challenge that points to the
  #   protected resource metadata and names the scopes (add-mcp-oauth
  #   design.md, decision 9), with error="invalid_token" once a token was
  #   refused. The SDK's Challenge builds them (harden-mcp-oauth design.md,
  #   decision 11).
  # - The first verifier that accepts the token's shape verifies it. A token
  #   no verifier accepts, or one its verifier rejects, gets 401.
  # - A connection's access token is confirmed with Goalner before any
  #   answer, whatever the request (harden-mcp-oauth design.md, decision 1):
  #   its first use completes refresh rotation, and an ended connection gets
  #   401 even for tools/list. A cached connection token needs no request.
  #   An exchange over its limit lets the request through; tool calls then
  #   get rate_limited.
  # - The credential goes to env["mcp.auth_info"], where the transport passes
  #   it to tool handlers. When a handler marks it rejected (the API answered
  #   401 mid-request), the request is answered 401 and the verifier forgets it.
  # - Goalner unreachable, or refusing the MCP server's own service key: 503.
  class Authentication
    BEARER = /\ABearer +(?<token>\S+)\z/
    SCOPE = ProtectedResource::SCOPES.join(" ")
    CHALLENGE = MCP::Server::OAuth::Challenge

    def initialize(app, verifiers:, resource_metadata_url:)
      @app = app
      @verifiers = verifiers
      @resource_metadata_url = resource_metadata_url
    end

    def call(env)
      token = BEARER.match(env["HTTP_AUTHORIZATION"].to_s.b)&.[](:token)
      return CHALLENGE.missing_token_response(scope: SCOPE, resource_metadata: @resource_metadata_url) unless token

      verifier = @verifiers.find { |candidate| candidate.accepts?(token) }
      credential = verifier&.verify(token)
      return invalid_token_response unless credential && confirmed?(credential)

      env[MCP::Server::OAuth::ENV_KEY] = credential
      status, headers, body = @app.call(env)
      return [ status, headers, body ] unless credential.rejected?

      body.close if body.respond_to?(:close)
      verifier.forget(credential)
      invalid_token_response
    rescue ApiClient::Unavailable
      [ 503, { "content-type" => "application/json" }, [ JSON.generate(UNAVAILABLE) ] ]
    end

    UNAVAILABLE = { jsonrpc: "2.0", id: nil, error: { code: -32603, message: ApiClient::UNAVAILABLE_MESSAGE } }.freeze

    private
      def invalid_token_response
        CHALLENGE.invalid_token_response(scope: SCOPE, resource_metadata: @resource_metadata_url)
      end

      def confirmed?(credential)
        credential.upstream_token if credential.connection?
        true
      rescue ConnectionTokens::Refused
        false
      rescue ConnectionTokens::RateLimited
        true
      end
  end
end
