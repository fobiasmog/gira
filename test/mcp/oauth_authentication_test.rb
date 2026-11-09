require_relative "support"
require "open3"

# Authentication by an MCP connection's access token, the protected resource
# metadata and the challenge (spec mcp-server, "Authentication" and
# "Protected resource metadata"; add-mcp-oauth design.md, decisions 2, 9 and 11).
class McpOauthAuthenticationTest < McpIntegrationTest
  CHALLENGE = { "resource_metadata" => goalner_url("/.well-known/oauth-protected-resource/mcp"), "scope" => "read write" }.freeze

  def signing_key
    OpenSSL::PKey::EC.new(Rails.application.credentials.dig(:mcp, :jwt_private_key))
  end

  # A JWT with Goalner's key and kid, and the claims given over valid ones.
  def jwt(**claims)
    now = Time.current.to_i
    payload = { iss: goalner_url, sub: users(:two).id.to_s, aud: goalner_url("/mcp"), client_id: "client",
                scope: "read write", iat: now, exp: now + 3600, jti: SecureRandom.uuid }.merge(claims).compact
    JWT.encode(payload, signing_key, "ES256", kid: JWT::JWK.new(signing_key, kid_generator: JWT::JWK::Thumbprint).kid)
  end

  # The verifier alone: through the application, a token is also confirmed
  # with Goalner, which knows none of the JWTs made up here.
  def jwt_verifier(public_keys = Oauth::JwtGenerator.public_key_pem)
    GoalnerMcp::JwtVerifier.new(metadata: GoalnerMcp::ProtectedResource.new(resource: Oauth.resource, issuer: Oauth.issuer).metadata,
      public_keys: public_keys, connection_tokens: Object.new)
  end

  test "connection access token: tools are listed, once Goalner confirmed it" do
    _api_token, _access_token, access_token = create_connection_token(users(:two))

    assert_not_empty mcp_result("tools/list", token: access_token)["tools"]
    assert_equal [ "POST /internal/mcp_token_exchange" ], api_requests
  end

  test "a signed JWT Goalner never issued: 401 with error=invalid_token" do
    response = mcp_request("tools/list", token: jwt)

    assert_equal 401, response.status
    assert_includes response.headers["www-authenticate"], 'error="invalid_token"'
  end

  test "expired access token: 401 with error=invalid_token" do
    response = mcp_request("tools/list", token: jwt(iat: 2.hours.ago.to_i, exp: 31.seconds.ago.to_i))

    assert_equal 401, response.status
    assert_includes response.headers["www-authenticate"], 'error="invalid_token"'
    assert_not_includes response.body, "tools"
  end

  test "an access token expired less than 30 seconds ago still verifies" do
    assert jwt_verifier.verify(jwt(exp: 20.seconds.ago.to_i))
    assert_nil jwt_verifier.verify(jwt(exp: 31.seconds.ago.to_i))
  end

  test "token for another audience: 401" do
    response = mcp_request("tools/list", token: jwt(aud: "https://other.example/mcp"))

    assert_equal 401, response.status
    assert_includes response.headers["www-authenticate"], 'error="invalid_token"'
  end

  test "another issuer, another key, no signature, or no expiry: 401" do
    other_key = OpenSSL::PKey::EC.generate("prime256v1")
    unsigned = [ { alg: "none" }, { sub: "2", aud: goalner_url("/mcp"), iss: goalner_url, exp: 1.hour.from_now.to_i } ]
      .map { Base64.urlsafe_encode64(JSON.generate(it), padding: false) }.join(".") + "."

    [ jwt(iss: "https://evil.example"), JWT.encode(JWT.decode(jwt, nil, false).first, other_key, "ES256"), unsigned,
      jwt(exp: nil), "not.a.jwt" ].each do |token|
      assert_equal 401, mcp_request("tools/list", token: token).status, token
    end
  end

  test "metadata at both well-known paths" do
    [ "/.well-known/oauth-protected-resource/mcp", "/.well-known/oauth-protected-resource" ].each do |path|
      get path

      assert_equal 200, last_response.status, path
      metadata = JSON.parse(last_response.body)
      assert_equal goalner_url("/mcp"), metadata["resource"]
      assert_equal [ goalner_url ], metadata["authorization_servers"]
      assert_equal %w[read write], metadata["scopes_supported"]
      assert_equal [ "header" ], metadata["bearer_methods_supported"]
    end
  end

  test "challenge: a request without a token gets 401 pointing to the metadata" do
    @app = build_app(public_url: goalner_url)
    post goalner_url("/mcp"), JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/list"),
      { "CONTENT_TYPE" => "application/json", "HTTP_ACCEPT" => "application/json, text/event-stream", "HTTP_MCP_PROTOCOL_VERSION" => "2025-11-25" }

    assert_equal 401, last_response.status
    assert_equal CHALLENGE, challenge_parameters(last_response)
  end

  test "a refused token's challenge also names the error" do
    @app = build_app(public_url: goalner_url)
    post goalner_url("/mcp"), JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/list"),
      { "CONTENT_TYPE" => "application/json", "HTTP_ACCEPT" => "application/json", "HTTP_MCP_PROTOCOL_VERSION" => "2025-11-25",
        "HTTP_AUTHORIZATION" => "Bearer #{jwt(aud: "https://other.example/mcp")}" }

    assert_equal CHALLENGE.merge("error" => "invalid_token"), challenge_parameters(last_response)
  end

  test "several public keys: a token signed by any of them verifies" do
    rotated = OpenSSL::PKey::EC.generate("prime256v1")
    verifier = jwt_verifier(rotated.public_to_pem + Oauth::JwtGenerator.public_key_pem)
    rotated_token = JWT.encode(JWT.decode(jwt, nil, false).first, rotated, "ES256",
      kid: JWT::JWK.new(rotated, kid_generator: JWT::JWK::Thumbprint).kid)

    assert verifier.verify(jwt)
    assert verifier.verify(rotated_token)
    assert_nil jwt_verifier.verify(rotated_token)
  end

  # The MCP process refuses to start in production without its OAuth and
  # exchange settings (design.md, decision 11), naming the missing one.
  test "production refuses to start without each setting" do
    complete = { "RACK_ENV" => "production", "GOALNER_API_URL" => "http://web:3000", "MCP_PUBLIC_URL" => goalner_url,
                 "MCP_RESOURCE_URL" => goalner_url("/mcp"), "MCP_ISSUER" => goalner_url,
                 "MCP_JWT_PUBLIC_KEYS" => Oauth::JwtGenerator.public_key_pem, "MCP_SERVICE_KEY" => "key", "REDIS_URL" => "redis://cache:6379/0",
                 "DATABASE_URL" => nil, "RAILS_MASTER_KEY" => nil, "RAILS_ENV" => nil }
    script = 'require "bundler/setup"; require "rack"; Rack::Builder.parse_file("mcp/config.ru"); puts "started"'

    output, errors, status = Open3.capture3(complete, RbConfig.ruby, "-e", script, chdir: Rails.root.to_s)
    assert status.success?, errors
    assert_includes output, "started"

    %w[MCP_JWT_PUBLIC_KEYS MCP_ISSUER MCP_RESOURCE_URL MCP_PUBLIC_URL MCP_SERVICE_KEY REDIS_URL].each do |name|
      _output, errors, status = Open3.capture3(complete.merge(name => nil), RbConfig.ruby, "-e", script, chdir: Rails.root.to_s)

      assert_not status.success?, name
      assert_includes errors, "#{name} must be set"
    end
  end
end
