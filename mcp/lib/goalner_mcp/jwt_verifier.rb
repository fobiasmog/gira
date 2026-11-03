module GoalnerMcp
  # Verifies the access tokens of MCP connections (spec mcp-server,
  # "Authentication"; add-mcp-oauth design.md, decisions 2 and 9): JWTs that
  # Goalner signed with ES256 for this resource. The signature, issuer,
  # audience and expiry (with 30 seconds of leeway) are checked locally, with
  # the SDK's verifier and the public keys in MCP_JWT_PUBLIC_KEYS, matched by
  # their RFC 7638 thumbprint, so keys can rotate.
  #
  # Verification alone never authorizes a tool call: the exchange for a
  # connection token checks the token against Goalner's database
  # (UpstreamCredential).
  class JwtVerifier
    ALGORITHM = "ES256"
    LEEWAY = 30
    PEM = /-----BEGIN PUBLIC KEY-----.+?-----END PUBLIC KEY-----/m

    # public_keys: one or more PEM public keys. A newline escaped as "\n", as
    # an env file holds it, counts as a newline.
    def initialize(metadata:, public_keys:, connection_tokens:)
      keys = public_keys.gsub("\\n", "\n").scan(PEM).map { |pem| JWT::JWK.new(OpenSSL::PKey.read(pem), kid_generator: JWT::JWK::Thumbprint).export }
      raise ArgumentError, "MCP_JWT_PUBLIC_KEYS holds no PEM public key" if keys.empty?

      @verifier = MCP::Server::OAuth::JWTVerifier.new(resource_metadata: metadata, jwks: { keys: keys },
        algorithms: [ ALGORITHM ], leeway: LEEWAY)
      @connection_tokens = connection_tokens
    end

    # Personal tokens have their own verifier; everything else is a JWT or
    # nothing.
    def accepts?(token)
      !token.start_with?(TokenVerifier::PREFIX)
    end

    # The credential, or nil for a token that does not verify.
    def verify(token)
      access_token = @verifier.verify(token)
      Credential.new(cache_key: Digest::SHA256.hexdigest(token), connection_tokens: @connection_tokens, **access_token_attributes(access_token))
    rescue MCP::Server::OAuth::InvalidTokenError
      nil
    end

    # The API refused the connection token: the next call exchanges again.
    def forget(credential)
      @connection_tokens.forget(credential)
    end

    private
      def access_token_attributes(access_token)
        { token: access_token.token, client_id: access_token.client_id, scopes: access_token.scopes,
          expires_at: access_token.expires_at, subject: access_token.subject, issuer: access_token.issuer,
          audience: access_token.audience, resource: access_token.resource, claims: access_token.claims }
      end
  end
end
