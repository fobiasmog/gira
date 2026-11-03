module GoalnerMcp
  # Authenticates every MCP request before the transport sees it (spec
  # mcp-server, "Authentication"; add-mcp-server design.md, decision 6).
  #
  # - Only the Authorization header counts: a token in the query string or the
  #   body never authenticates. No header, another scheme, or a malformed
  #   Bearer value gets 401 with a Bearer challenge that points to the
  #   protected resource metadata (Challenge; add-mcp-oauth design.md,
  #   decision 9), with error="invalid_token" once a token was refused.
  # - The header follows RFC 6750 section 2.1: "Bearer" in any case, one or
  #   more spaces, and a b64token (letters, digits, "-._~+/", then optional
  #   trailing "="). Any other character makes the value malformed.
  # - The first verifier that accepts the token's shape verifies it. A token
  #   no verifier accepts, or one its verifier rejects, gets 401.
  # - The credential goes to env["mcp.auth_info"], where the transport passes
  #   it to tool handlers. When a handler marks it rejected (the API answered
  #   401 mid-request), the request is answered 401 and the verifier forgets it.
  class Authentication
    BEARER = %r{\ABearer +(?<token>[A-Za-z0-9\-._~+/]+=*)\z}i

    def initialize(app, verifiers:, challenge:)
      @app = app
      @verifiers = verifiers
      @challenge = challenge
    end

    def call(env)
      token = BEARER.match(env["HTTP_AUTHORIZATION"].to_s.b)&.[](:token)
      return @challenge.missing_token_response unless token

      verifier = @verifiers.find { |candidate| candidate.accepts?(token) }
      credential = verifier&.verify(token)
      return @challenge.invalid_token_response unless credential

      env[MCP::Server::OAuth::ENV_KEY] = credential
      status, headers, body = @app.call(env)
      return [ status, headers, body ] unless credential.rejected?

      body.close if body.respond_to?(:close)
      verifier.forget(credential)
      @challenge.invalid_token_response
    rescue ApiClient::Unavailable
      [ 503, { "content-type" => "application/json" }, [ JSON.generate(UNAVAILABLE) ] ]
    end

    UNAVAILABLE = { jsonrpc: "2.0", id: nil, error: { code: -32603, message: ApiClient::UNAVAILABLE_MESSAGE } }.freeze
  end
end
