require "test_helper"

# The connection token exchange (spec api-tokens, "Connection tokens" and
# "Token rate limits"; spec security-baseline, "Deny by default"; spec
# mcp-authorization, "Access tokens" and "Refresh tokens"; add-mcp-oauth
# design.md, decision 8). two is a member of goal and side.
class Internal::McpTokensControllerTest < ActionDispatch::IntegrationTest
  SERVICE_KEY = { "X-Goalner-Service-Key" => "development-mcp-service-key" }.freeze

  setup do
    @client = oauth_applications(:claude_ai)
  end

  def exchange(access_token, headers: SERVICE_KEY)
    post internal_mcp_tokens_path, params: { access_token: access_token }, headers: headers
  end

  def bearer(value)
    { "Authorization" => "Bearer #{value}" }
  end

  # Signs new access tokens with key while the block runs, as after rotation.
  def with_signing_key(key)
    generator = Oauth::JwtGenerator
    original = generator.instance_variable_get(:@private_key), generator.instance_variable_get(:@jwk)
    generator.instance_variable_set(:@private_key, key)
    generator.instance_variable_set(:@jwk, nil)
    yield
  ensure
    generator.instance_variable_set(:@private_key, original[0])
    generator.instance_variable_set(:@jwk, original[1])
  end

  test "exchange: a connection token that expires no later than the access token and acts as Alice in all of her projects" do
    tokens = connect(users(:two), @client, access: "read_write")
    access_expiry = Time.zone.at(decode_access_token(tokens["access_token"]).first["exp"])

    assert_difference -> { ApiToken.count } do
      exchange tokens["access_token"]
    end

    assert_response :created
    body = response.parsed_body
    assert_equal "read_write", body["access"]
    assert_operator Time.zone.parse(body["expires_at"]), :<=, access_expiry
    assert_match(/\Aglnr_/, body["token"])

    get api_projects_path, headers: bearer(body["token"])
    assert_equal [ projects(:goal).id, projects(:side).id ].sort, response.parsed_body.map { it["id"] }.sort
    post api_project_tasks_path(projects(:side)), params: { title: "Via Claude" }, headers: bearer(body["token"]), as: :json
    assert_equal users(:two), Task.find_by!(title: "Via Claude").creator
  end

  test "the stored connection token is a digest, tied to the access token" do
    tokens = connect(users(:two), @client)
    exchange tokens["access_token"]

    api_token = ApiToken.of_connections.sole
    assert_equal Oauth::AccessToken.by_token(tokens["access_token"]), api_token.oauth_access_token
    assert_equal "Claude", api_token.name
    assert_not_equal response.parsed_body["token"], api_token.token_digest
  end

  test "wrong service key: 401 and no token" do
    tokens = connect(users(:two), @client)

    assert_no_difference -> { ApiToken.count } do
      [ {}, { "X-Goalner-Service-Key" => "wrong" }, { "X-Goalner-Service-Key" => "" } ].each do |headers|
        exchange tokens["access_token"], headers: headers
        assert_response :unauthorized
      end
    end
  end

  test "internal exchange without the service key, even with a signed-in session: 401" do
    tokens = connect(users(:two), @client)
    sign_in_as users(:two)

    assert_no_difference -> { ApiToken.count } do
      exchange tokens["access_token"], headers: {}
    end
    assert_response :unauthorized
  end

  test "an unset service key refuses everything" do
    tokens = connect(users(:two), @client)
    original = Rails.configuration.x.oauth.service_key
    Rails.configuration.x.oauth.service_key = nil

    exchange tokens["access_token"], headers: { "X-Goalner-Service-Key" => "" }
    assert_response :unauthorized
  ensure
    Rails.configuration.x.oauth.service_key = original
  end

  test "ended connection: 401 and no token" do
    tokens = connect(users(:two), @client)
    Oauth::AccessToken.by_token(tokens["access_token"]).revoke

    assert_no_difference -> { ApiToken.count } do
      exchange tokens["access_token"]
    end
    assert_response :unauthorized
    assert_equal "invalid_token", response.parsed_body["error"]
  end

  test "expired, unknown, personal or forged access tokens: 401" do
    tokens = connect(users(:two), @client)
    forged = JWT.encode(decode_access_token(tokens["access_token"]).first, OpenSSL::PKey::EC.generate("prime256v1"), "ES256")

    [ forged, "unknown", "glnr_two_goal_read", "", nil ].each do |value|
      exchange value
      assert_response :unauthorized, value.inspect
    end

    travel 1.hour + 1.second
    exchange tokens["access_token"]
    assert_response :unauthorized
  end

  test "a token issued for another resource: 401" do
    tokens = connect(users(:two), @client)
    original = Rails.configuration.x.oauth.resource
    Rails.configuration.x.oauth.resource = "https://other.example/mcp"

    exchange tokens["access_token"]
    assert_response :unauthorized
  ensure
    Rails.configuration.x.oauth.resource = original
  end

  # Spec mcp-authorization, "Name from a long host"; harden-mcp-oauth
  # design.md, decision 5.
  test "a client whose stored name has 130 characters: the connection token takes the first 100" do
    client = Oauth::Application.create!(name: "x" * 130, redirect_uri: "https://long.example/cb", registration: :dcr)
    tokens = connect(users(:two), client)

    exchange tokens["access_token"]

    assert_response :created
    assert_equal "x" * 100, ApiToken.of_connections.sole.name
  end

  # Spec api-tokens, "Previous signing key"; harden-mcp-oauth design.md,
  # decision 4.
  test "previous signing key: a live access token the replaced key signed is exchanged" do
    tokens = connect(users(:two), @client)

    with_signing_key(OpenSSL::PKey::EC.generate("prime256v1")) { exchange tokens["access_token"] }

    assert_response :created
  end

  test "a live token row whose JWT names another audience: 401" do
    original = Rails.configuration.x.oauth.resource
    Rails.configuration.x.oauth.resource = "https://other.example/mcp"
    _api_token, _access_token, jwt = create_connection_token(users(:two), application: @client)
    Rails.configuration.x.oauth.resource = original

    exchange jwt
    assert_response :unauthorized
  ensure
    Rails.configuration.x.oauth.resource = original
  end

  test "disconnected while in use: the next request with the connection token gets 401" do
    tokens = connect(users(:two), @client)
    exchange tokens["access_token"]
    connection_token = response.parsed_body["token"]

    McpConnection.find(users(:two), @client.id).disconnect!

    get api_projects_path, headers: bearer(connection_token)
    assert_response :unauthorized
  end

  test "read-only connection: insufficient_scope when creating a task" do
    tokens = connect(users(:two), @client, access: "read")
    exchange tokens["access_token"]
    assert_equal "read", response.parsed_body["access"]

    assert_no_difference -> { Task.count } do
      post api_project_tasks_path(projects(:goal)), params: { title: "Nope" }, headers: bearer(response.parsed_body["token"]), as: :json
    end
    assert_response :forbidden
    assert_equal "insufficient_scope", response.parsed_body.dig("error", "code")
  end

  test "exchange burst: the 61st exchange of one access token within an hour gets 429" do
    tokens = connect(users(:two), @client)
    60.times { exchange tokens["access_token"] }
    assert_response :created

    assert_no_difference -> { ApiToken.count } do
      exchange tokens["access_token"]
    end
    assert_response :too_many_requests

    other = refresh(tokens["refresh_token"], @client)
    exchange other["access_token"]
    assert_response :created
  end

  test "access token at the API: 401" do
    tokens = connect(users(:two), @client, access: "read_write")

    get api_me_path, headers: bearer(tokens["access_token"])
    assert_response :unauthorized
  end

  test "old refresh token: once the new access token is exchanged, the refresh token it replaced gets invalid_grant" do
    tokens = connect(users(:two), @client)
    refreshed = refresh(tokens["refresh_token"], @client)

    exchange refreshed["access_token"]
    assert_response :created

    assert_equal "invalid_grant", refresh(tokens["refresh_token"], @client)["error"]
    assert refresh(refreshed["refresh_token"], @client)["access_token"]
  end

  test "before the new access token is used, the replaced refresh token still works once" do
    tokens = connect(users(:two), @client)
    refresh(tokens["refresh_token"], @client)

    assert refresh(tokens["refresh_token"], @client)["access_token"]
  end
end
