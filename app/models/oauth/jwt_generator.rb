# Doorkeeper's access token generator (spec mcp-authorization, "Access
# tokens"; add-mcp-oauth design.md, decision 2). Each access token is a JWT
# signed with ES256 for the MCP endpoint alone, so the MCP server can verify
# it with the public key. Doorkeeper stores only its SHA-256 digest.
#
# The private key is the EC P-256 key in the credentials (mcp.jwt_private_key);
# the key id is its RFC 7638 thumbprint, so the MCP server can hold several
# public keys while the key is rotated.
module Oauth::JwtGenerator
  ALGORITHM = "ES256"

  class << self
    # Called by Doorkeeper with the token's attributes.
    def generate(attributes)
      issued_at = attributes.fetch(:created_at).to_i
      payload = {
        iss: Oauth.issuer,
        sub: attributes.fetch(:resource_owner_id).to_s,
        aud: Oauth.resource,
        client_id: attributes.fetch(:application).uid,
        scope: attributes.fetch(:scopes).to_s,
        iat: issued_at,
        exp: issued_at + attributes.fetch(:expires_in).to_i,
        jti: SecureRandom.uuid
      }

      JWT.encode(payload, private_key, ALGORITHM, kid: jwk.kid)
    end

    # The verified claims of a token this application issued for the current
    # resource, or nil. Expiry is left to the token's database row.
    def decode(token)
      claims, _header = JWT.decode(token.to_s, private_key, true,
        algorithm: ALGORITHM, iss: Oauth.issuer, verify_iss: true, aud: Oauth.resource, verify_aud: true,
        verify_expiration: false)
      claims
    rescue JWT::DecodeError
      nil
    end

    # The public key, as the MCP server takes it (MCP_JWT_PUBLIC_KEYS).
    def public_key_pem
      private_key.public_to_pem
    end

    private
      def private_key
        @private_key ||= OpenSSL::PKey::EC.new(private_key_pem)
      end

      # Development without the credential uses a key of its own in tmp/,
      # as Rails does for secret_key_base; bin/dev hands its public key to
      # the MCP server.
      def private_key_pem
        pem = Rails.application.credentials.dig(:mcp, :jwt_private_key)
        return pem if pem.present?
        raise KeyError, "mcp.jwt_private_key is missing from the credentials" unless Rails.env.development?

        path = Rails.root.join("tmp/development_mcp_jwt_key.pem")
        path.write(OpenSSL::PKey::EC.generate("prime256v1").to_pem) unless path.exist?
        path.read
      end

      def jwk
        @jwk ||= JWT::JWK.new(private_key, kid_generator: JWT::JWK::Thumbprint)
      end
  end
end
