require "test_helper"

# Connected apps and how connections end (spec mcp-authorization, "Connected
# apps" and "Connection lifetime"; spec user-auth, "Password reset" and
# "Change password from settings"; add-mcp-oauth design.md, decision 7).
class Api::Me::ConnectionsControllerTest < ActionDispatch::IntegrationTest
  SERVICE_KEY = { "X-Goalner-Service-Key" => "development-mcp-service-key" }.freeze
  PASSWORD = SessionTestHelper::PASSWORD

  setup do
    @claude = oauth_applications(:claude_ai)
    @claude_code = oauth_applications(:claude_code)
  end

  def exchange(access_token)
    post internal_mcp_tokens_path, params: { access_token: access_token }, headers: SERVICE_KEY
    response
  end

  def connections
    get api_me_connections_path
    assert_response :success
    response.parsed_body
  end

  # The access token and refresh token still work: a connection token, and
  # a refreshed pair.
  def assert_connection_works(tokens, client)
    assert_equal 201, exchange(tokens["access_token"]).status
    assert refresh(tokens["refresh_token"], client)["access_token"]
  end

  def assert_connection_ended(tokens, client)
    assert_equal 401, exchange(tokens["access_token"]).status
    assert_equal "invalid_grant", refresh(tokens["refresh_token"], client)["error"]
  end

  test "list: claude.ai's name, the host claude.ai, read-write, and the connection and last-active times" do
    connected_at = Time.current
    tokens = connect(users(:two), @claude, access: "read_write")
    travel 3.hours
    3.times { tokens = refresh(tokens["refresh_token"], @claude).tap { exchange(it["access_token"]) } }

    connection = connections.sole
    assert_equal [ @claude.id, "Claude", "claude.ai", "read_write" ],
      connection.values_at("id", "client_name", "redirect_host", "access")
    assert_in_delta connected_at, Time.zone.parse(connection["connected_at"]), 2
    assert_in_delta Time.current, Time.zone.parse(connection["last_active_at"]), 2
  end

  test "each client is its own connection, with its own access" do
    connect(users(:two), @claude, access: "read")
    connect(users(:two), @claude_code, access: "read_write")

    assert_equal [ [ "Claude", "read" ], [ "Claude Code", "read_write" ] ],
      connections.map { it.values_at("client_name", "access") }.sort
  end

  test "a connection made again after disconnecting starts anew" do
    connect(users(:two), @claude)
    McpConnection.find(users(:two), @claude.id).disconnect!
    travel 1.day
    connect(users(:two), @claude)

    assert_in_delta Time.current, Time.zone.parse(connections.sole["connected_at"]), 2
  end

  test "an approved code not yet exchanged is a connection, and disconnecting it voids the code" do
    sign_in_as users(:two)
    code = approve(authorization_params(@claude))
    assert_equal [ "Claude" ], connections.map { it["client_name"] }

    delete api_me_connection_path(@claude.id)
    assert_equal "invalid_grant", exchange_code(code, @claude)["error"]
  end

  test "denying creates no connection" do
    sign_in_as users(:two)
    delete oauth_authorization_path, params: authorization_params(@claude)

    assert_empty connections
  end

  test "disconnected: the next tool call's exchange and the connection token get 401, and the refresh invalid_grant" do
    tokens = connect(users(:two), @claude, access: "read_write")
    connection_token = exchange(tokens["access_token"]).parsed_body["token"]

    delete api_me_connection_path(@claude.id)
    assert_response :no_content

    get api_projects_path, headers: { "Authorization" => "Bearer #{connection_token}" }
    assert_response :unauthorized
    assert_connection_ended tokens, @claude
    assert_empty connections
  end

  test "disconnecting one client leaves the others" do
    claude = connect(users(:two), @claude)
    claude_code = connect(users(:two), @claude_code)

    delete api_me_connection_path(@claude.id)

    assert_connection_ended claude, @claude
    assert_connection_works claude_code, @claude_code
  end

  test "another user's connection: 404, and the connection keeps working" do
    tokens = connect(users(:two), @claude)
    sign_in_as users(:one)

    delete api_me_connection_path(@claude.id)

    assert_response :not_found
    assert_empty connections
    assert_connection_works tokens, @claude
  end

  test "token request: an API token or a connection token gets 403" do
    connection_token, = create_connection_token(users(:two))

    [ "glnr_two_goal_read_write", connection_token.value ].each do |value|
      get api_me_connections_path, headers: { "Authorization" => "Bearer #{value}" }
      assert_response :forbidden
      assert_equal "token_not_allowed", response.parsed_body.dig("error", "code")

      delete api_me_connection_path(@claude.id), headers: { "Authorization" => "Bearer #{value}" }
      assert_response :forbidden
    end
  end

  test "signed out: 401" do
    get api_me_connections_path

    assert_response :unauthorized
  end

  test "password changed: both connections end, and the list is empty" do
    claude = connect(users(:two), @claude)
    claude_code = connect(users(:two), @claude_code)
    other_user = connect(users(:one), @claude)

    sign_in_as users(:two)
    patch api_me_password_path, params: { current_password: PASSWORD, password: "a brand new password" }, as: :json
    assert_response :no_content

    assert_connection_ended claude, @claude
    assert_connection_ended claude_code, @claude_code
    assert_empty connections
    assert_connection_works other_user, @claude
  end

  test "connections end on reset: the next MCP request gets 401 and the refresh invalid_grant" do
    tokens = connect(users(:two), @claude)
    reset!

    put password_path(users(:two).password_reset_token), params: { password: "a brand new password", password_confirmation: "a brand new password" }

    assert_connection_ended tokens, @claude
  end

  test "the guide linked from an empty list is the README's MCP section" do
    get mcp_guide_path

    assert_redirected_to "https://github.com/fobiasmog/gira#mcp-server"
  end
end
