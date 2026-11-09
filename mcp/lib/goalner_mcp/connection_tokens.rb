module GoalnerMcp
  # Connection tokens for MCP connections (spec mcp-server, "Tool calls act
  # as the token"; add-mcp-oauth design.md, decisions 8 and 9). A tool call
  # with a connection's access token sends the API a connection token
  # instead, which Goalner issues in exchange for the access token and the
  # service key (POST /internal/mcp_token_exchange). Goalner checks the access token
  # against its database there, and its first exchange completes refresh
  # rotation. Authentication exchanges before answering any request made
  # with a new access token, so a JWT that merely verifies can neither list
  # tools nor call one (harden-mcp-oauth design.md, decision 1).
  #
  # Each connection token is cached until 30 seconds before it expires, under
  # the SHA-256 of the access token, encrypted with AES-256-GCM under a key
  # derived from the access token itself (HKDF-SHA256). The cache alone, such
  # as a Redis dump, yields neither the connection token nor the access token.
  # Cache errors are logged and count as misses; the exchange's own limit (60
  # an hour per access token) bounds the extra load.
  class ConnectionTokens
    KEY_PREFIX = "mcp:ct:"
    HKDF_SALT = "goalner-mcp-connection-token-cache"
    HKDF_INFO = "goalner-mcp-connection-token"
    EXPIRY_MARGIN = 30
    EXCHANGE_PATH = "/internal/mcp_token_exchange"

    # The exchange refused the access token (invalid_token): the connection
    # ended. The client gets 401, which makes it refresh or sign in again.
    # Any other 401, such as a wrong service key, is the MCP server's own
    # fault and raises ApiClient::Unavailable, so clients keep their tokens
    # (harden-mcp-oauth design.md, decision 3).
    class Refused < StandardError; end

    # The access token was exchanged 60 times within the hour.
    class RateLimited < StandardError; end

    def initialize(api, service_key:, cache:)
      @api = api
      @service_key = service_key
      @cache = cache
    end

    # The connection token to send the API for credential.
    def token_for(credential)
      key = cache_key(credential.token)
      cached = decrypt(credential.token, key, cache { @cache.read(key) })
      return cached if cached

      token, expires_at = exchange(credential.token)
      ttl = expires_at - Time.now.to_i - EXPIRY_MARGIN
      cache { @cache.write(key, encrypt(credential.token, key, token), ttl: ttl) } if ttl.positive?
      token
    end

    # Drops the cached connection token, after the API refused it.
    def forget(credential)
      cache { @cache.delete(cache_key(credential.token)) }
    end

    def cache_key(access_token)
      KEY_PREFIX + Digest::SHA256.hexdigest(access_token)
    end

    private
      def exchange(access_token)
        response = @api.request("POST", EXCHANGE_PATH, headers: { "X-Goalner-Service-Key" => @service_key },
          body: { access_token: access_token })

        case response.status
        when 201
          body = JSON.parse(response.body)
          [ body.fetch("token"), Time.iso8601(body.fetch("expires_at")).to_i ]
        when 401
          raise Refused if error_code(response.body) == "invalid_token"

          GoalnerMcp.logger.error("Connection token exchange refused the MCP server's credentials; check MCP_SERVICE_KEY")
          raise ApiClient::Unavailable, "the exchange refused the MCP server's credentials"
        when 429 then raise RateLimited
        else
          GoalnerMcp.logger.error("Connection token exchange answered #{response.status}")
          raise ApiClient::Unavailable, "the exchange answered #{response.status}"
        end
      rescue JSON::ParserError, KeyError, ArgumentError
        GoalnerMcp.logger.error("Connection token exchange answered without a token")
        raise ApiClient::Unavailable, "the exchange answered without a token"
      end

      def error_code(body)
        parsed = JSON.parse(body.to_s)
        parsed["error"] if parsed.is_a?(Hash)
      rescue JSON::ParserError
        nil
      end

      def encryption_key(access_token)
        OpenSSL::KDF.hkdf(access_token, salt: HKDF_SALT, info: HKDF_INFO, length: 32, hash: "SHA256")
      end

      # nonce, ciphertext and tag, Base64-encoded; the cache key is
      # authenticated too, so an entry cannot be moved to another key.
      def encrypt(access_token, key, token)
        cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
        cipher.key = encryption_key(access_token)
        nonce = cipher.random_iv
        cipher.auth_data = key
        ciphertext = cipher.update(token) + cipher.final
        [ nonce + cipher.auth_tag + ciphertext ].pack("m0")
      end

      def decrypt(access_token, key, entry)
        return unless entry.is_a?(String)

        raw = entry.unpack1("m0")
        cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
        cipher.key = encryption_key(access_token)
        cipher.iv = raw.byteslice(0, 12)
        cipher.auth_tag = raw.byteslice(12, 16)
        cipher.auth_data = key
        cipher.update(raw.byteslice(28..)) + cipher.final
      rescue OpenSSL::Cipher::CipherError, ArgumentError, TypeError
        nil
      end

      def cache
        yield
      rescue StandardError => error
        GoalnerMcp.logger.error("Connection token cache failed: #{error.class}")
        nil
      end
  end

  # The cache in Redis (REDIS_URL), shared by the MCP processes. Short
  # timeouts and no reconnection attempts: a miss costs one exchange.
  class RedisCache
    def initialize(url)
      @redis = Redis.new(url: url, connect_timeout: 0.5, read_timeout: 0.5, write_timeout: 0.5, reconnect_attempts: 0)
    end

    def read(key)
      @redis.get(key)
    end

    def write(key, value, ttl:)
      @redis.set(key, value, ex: ttl)
    end

    def delete(key)
      @redis.del(key)
    end
  end
end
