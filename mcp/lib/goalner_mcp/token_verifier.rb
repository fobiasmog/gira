module GoalnerMcp
  # Verifies personal API tokens (spec mcp-server, "Authentication"; add-mcp-
  # server design.md, decision 6) by asking the API: GET /api/me. A success is
  # remembered for TTL seconds, keyed by the token's SHA-256, so each token
  # costs at most one extra API request a minute per process.
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
    def verify(token)
      key = Digest::SHA256.hexdigest(token)
      return Credential.new(token: token, cache_key: key) if @cache.read(key)

      case @api.request("GET", "/api/me", token: token).status
      when 200
        @cache.write(key, true)
        Credential.new(token: token, cache_key: key)
      when 429
        # The API limits a token's requests only once it has authenticated
        # it, so the token is valid; tool calls then get rate_limited.
        Credential.new(token: token, cache_key: key)
      when 401
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
