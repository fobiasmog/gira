module GoalnerMcp
  # Verifies personal API tokens and agents' tokens (spec mcp-server,
  # "Authentication" and "Agent tokens at the MCP endpoint"; add-mcp-server
  # design.md, decision 6) by asking the API: GET /api/me. A success is
  # remembered for TTL seconds, keyed by the token's SHA-256, so each token
  # costs at most one extra API request a minute per process.
  #
  # The API refuses an agent's token that was not issued for MCP like an
  # unknown one. A 401 that does not say invalid_token is not about the
  # token: the API refused the MCP server's own service key, and the client
  # is told that Goalner is unavailable (add-agents design.md, decision 7).
  class TokenVerifier
    PREFIX = "glnr_"
    TTL = 60
    MAX_ENTRIES = 10_000

    def initialize(api, cache: LruCache.new(max_size: MAX_ENTRIES, ttl: TTL))
      @api = api
      @cache = cache
    end

    def accepts?(token)
      token.start_with?(PREFIX)
    end

    # The credential, or nil when the API rejects the token. Raises
    # ApiClient::Unavailable when the API cannot tell.
    #
    # The credential is built before anything is cached, so a failure to build
    # it never leaves the token remembered as verified.
    def verify(token)
      key = Digest::SHA256.hexdigest(token)
      credential = Credential.new(token: token, cache_key: key)
      return credential if @cache.read(key)

      response = @api.request("GET", "/api/me", token: token)
      case response.status
      when 200
        @cache.write(key, true)
        credential
      when 429
        # The API limits a token's requests only once it has authenticated
        # it, so the token is valid; tool calls then get rate_limited.
        credential
      when 401
        ApiClient.refused_credentials! unless ApiClient.error_code(response.body) == "invalid_token"
        nil
      else
        raise ApiClient::Unavailable, "GET /api/me answered an unexpected status"
      end
    end

    def forget(credential)
      @cache.delete(credential.cache_key)
    end
  end
end
