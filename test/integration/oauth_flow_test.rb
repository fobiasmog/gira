require "test_helper"
require "support/forgery_protected_integration_test"

# The OAuth authorization code flow end to end (spec mcp-authorization,
# "Access tokens" and "Refresh tokens"; add-mcp-oauth design.md, decisions 1
# and 2), with a fixture public client.
class OauthFlowTest < ActionDispatch::IntegrationTest
  setup do
    @client = oauth_applications(:cursor)
  end

  test "a signed-in user approves, and the code and verifier, form-encoded, yield a JWT and a refresh token" do
    tokens = connect(users(:two), @client, access: "read_write")

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal "Bearer", tokens["token_type"]
    assert_equal 3600, tokens["expires_in"]
    assert_equal "read write", tokens["scope"]
    assert tokens["refresh_token"].present?

    claims, header = decode_access_token(tokens["access_token"])
    assert_equal "ES256", header["alg"]
    assert header["kid"].present?
    assert_equal "https://goalner.com", claims["iss"]
    assert_equal users(:two).id.to_s, claims["sub"]
    assert_equal "https://goalner.com/mcp", claims["aud"]
    assert_equal @client.uid, claims["client_id"]
    assert_equal "read write", claims["scope"]
    assert_equal 3600, claims["exp"] - claims["iat"]
    assert_in_delta Time.current.to_i, claims["iat"], 5
    assert claims["jti"].present?
  end

  test "only digests are stored" do
    tokens = connect(users(:two), @client)
    stored = Oauth::AccessToken.sole

    assert_not_equal tokens["access_token"], stored.token
    assert_not_equal tokens["refresh_token"], stored.refresh_token
    assert_equal stored, Oauth::AccessToken.by_token(tokens["access_token"])
    assert_equal stored, Oauth::AccessToken.by_refresh_token(tokens["refresh_token"])
    assert_not_includes Oauth::AccessGrant.pluck(:token).join, tokens["access_token"]
  end

  test "each token is a fresh JWT" do
    first = connect(users(:two), @client)
    second = refresh(first["refresh_token"], @client)

    assert_not_equal decode_access_token(first["access_token"]).first["jti"], decode_access_token(second["access_token"]).first["jti"]
  end

  test "a JWT signed by another key, or with tampered claims, does not verify" do
    token = connect(users(:two), @client)["access_token"]
    other_key = OpenSSL::PKey::EC.generate("prime256v1")
    forged = JWT.encode(decode_access_token(token).first.merge("sub" => users(:one).id.to_s), other_key, "ES256")

    assert_raises(JWT::VerificationError) { decode_access_token(forged) }
    assert_nil Oauth::JwtGenerator.decode(forged)
    assert_equal users(:two).id.to_s, Oauth::JwtGenerator.decode(token)["sub"]
  end

  test "client administration, authorized applications and token info are not routed" do
    sign_in_as users(:two)

    [ "/oauth/applications", "/oauth/applications/new", "/oauth/authorized_applications", "/oauth/token/info",
      "/oauth/introspect" ].each do |path|
      get path
      assert_response :not_found, path
    end
    post "/oauth/introspect", params: { token: "x" }
    assert_response :not_found
  end
end

class OauthFlowForgeryTest < ForgeryProtectedIntegrationTest
  test "the consent POST without a CSRF token is rejected, and the token endpoint needs none" do
    client = oauth_applications(:cursor)
    sign_in_as users(:two)
    params = authorization_params(client)
    get oauth_authorization_path(params)
    assert_response :success
    token = css_select("form.consent__form input[name=authenticity_token]").sole["value"]

    post oauth_authorization_path, params: params.merge(access: "read")
    assert_response :unprocessable_content
    delete oauth_authorization_path, params: params
    assert_response :unprocessable_content
    assert_empty Oauth::AccessGrant.all

    post oauth_authorization_path, params: params.merge(access: "read", authenticity_token: token)
    code = redirect_query(response.location).fetch("code")

    reset!
    tokens = exchange_code(code, client)
    assert_response :success
    assert tokens["access_token"].present?
  end
end
