require_relative "support"

# Tool calls of MCP connections: the access token is exchanged for a
# connection token, cached encrypted (spec mcp-server, "Authentication" and
# "Tool calls act as the token"; spec mcp-authorization, "Connection reach";
# add-mcp-oauth design.md, decisions 8 and 9). two is a member of goal and side.
class McpConnectionTokensTest < McpIntegrationTest
  EXCHANGE = "POST /internal/mcp_tokens"

  # Raises on every call, like an unreachable Redis.
  class BrokenCache
    def read(*) = raise(Errno::ECONNREFUSED)
    def write(*, **) = raise(Errno::ECONNREFUSED)
    def delete(*) = raise(Errno::ECONNREFUSED)
  end

  setup do
    @goal = projects(:goal)
    @side = projects(:side)
    @cache = GoalnerMcp::LruCache.new(max_size: 100, ttl: 3600)
    @app = build_app(connection_token_cache: @cache)
    @jwt = new_access_token
  end

  def new_access_token(user = users(:two), scopes: "read write")
    Oauth::AccessToken.create!(application: oauth_applications(:claude_ai), resource_owner_id: user.id, scopes: scopes,
      expires_in: 3600, use_refresh_token: true).plaintext_token
  end

  def default_token
    @jwt
  end

  def call_tool(name, arguments = {}, token: default_token)
    mcp_result("tools/call", { name: name, arguments: arguments }, token: token)
  end

  def text(result)
    result.fetch("content").sole.fetch("text")
  end

  def exchanges
    api_requests.count(EXCHANGE)
  end

  def cache_key(jwt = @jwt)
    GoalnerMcp::ConnectionTokens::KEY_PREFIX + Digest::SHA256.hexdigest(jwt)
  end

  test "a second tool call with the same access token makes no exchange" do
    call_tool("listProjects")
    call_tool("listProjects")

    assert_equal [ EXCHANGE, "GET /api/projects", "GET /api/projects" ], api_requests
  end

  test "the cached value contains neither the connection token nor the access token, and another access token cannot decrypt it" do
    exchanged = nil
    transport = @api_transport
    original = transport.method(:call)
    transport.define_singleton_method(:call) do |method, path, headers, body|
      original.call(method, path, headers, body).tap { |status, response| exchanged = JSON.parse(response)["token"] if "#{method} #{path}" == EXCHANGE }
    end
    call_tool("listProjects")

    entry = @cache.read(cache_key)
    assert_match(/\Aglnr_/, exchanged)
    [ exchanged, @jwt, [ exchanged ].pack("m0"), Digest::SHA256.hexdigest(exchanged) ].each do |secret|
      assert_not_includes entry, secret
      assert_not_includes entry.unpack1("m0"), secret
    end

    tokens = GoalnerMcp::ConnectionTokens.new(nil, service_key: nil, cache: @cache)
    assert_equal exchanged, tokens.send(:decrypt, @jwt, cache_key, entry)
    assert_nil tokens.send(:decrypt, new_access_token, cache_key, entry)
    assert_nil tokens.send(:decrypt, @jwt, cache_key(new_access_token), entry), "an entry cannot move to another key"
  end

  test "the entry expires 30 seconds before the connection token" do
    now = 0
    cache = GoalnerMcp::LruCache.new(max_size: 10, ttl: 3600, clock: -> { now })
    @app = build_app(connection_token_cache: cache)
    call_tool("listProjects")

    now = 3600 - 31
    assert cache.read(cache_key)
    now = 3600 - 29
    assert_nil cache.read(cache_key)
  end

  test "connection ended between calls: 401, and nothing changes" do
    assert_not_empty mcp_result("tools/list")["tools"]
    call_tool("listProjects")
    McpConnection.find(users(:two), oauth_applications(:claude_ai).id).disconnect!

    assert_no_difference -> { Task.count } do
      response = mcp_request("tools/call", { name: "createTask", arguments: { project_id: @goal.id, title: "Late" } })

      assert_equal 401, response.status
      assert_includes response.headers["www-authenticate"], 'error="invalid_token"'
    end
    assert_nil @cache.read(cache_key), "the refused connection token is forgotten"

    assert_equal 401, mcp_request("tools/call", { name: "listProjects", arguments: {} }).status
    assert_equal 2, exchanges
  end

  test "a connection token the API refuses is exchanged again while the connection lives" do
    call_tool("listProjects")
    ApiToken.of_connections.delete_all

    assert_equal 401, mcp_request("tools/call", { name: "listProjects", arguments: {} }).status
    assert_not call_tool("listProjects")["isError"]
    assert_equal 2, exchanges
  end

  test "connection across projects: createTask in GOAL and in SIDE, both by Alice" do
    [ @goal, @side ].each do |project|
      result = call_tool("createTask", { project_id: project.id, title: "Across" })

      assert_not result["isError"], text(result)
      assert_equal users(:two), project.tasks.find_by!(title: "Across").creator
    end
    assert_equal 1, exchanges
  end

  test "project joined later: listed" do
    call_tool("listProjects")
    joined = Project.create!(title: "Joined", short_name: "JOIN", owner: users(:one))
    joined.memberships.create!(user: users(:two))

    ids = JSON.parse(text(call_tool("listProjects"))).map { it["id"] }

    assert_includes ids, joined.id
  end

  test "project left: not_found for it, and the connection keeps working for the others" do
    @goal.remove_member!(users(:two))

    result = call_tool("listTasks", { project_id: @goal.id })
    assert result["isError"]
    assert_equal "not_found: Not found.", text(result)

    assert_not call_tool("listTasks", { project_id: @side.id })["isError"]
  end

  test "a cache that raises on every call still serves tool calls through the exchange" do
    @app = build_app(connection_token_cache: BrokenCache.new)

    2.times { assert_not call_tool("listProjects")["isError"] }

    assert_equal 2, exchanges
  end

  test "exchange burst: once the access token was exchanged 60 times within the hour, tool calls get rate_limited" do
    @app = build_app(connection_token_cache: BrokenCache.new)
    Internal::McpTokensController::EXCHANGES_PER_HOUR.times { call_tool("listProjects") }

    assert_no_difference -> { Task.count } do
      result = call_tool("createTask", { project_id: @goal.id, title: "Too many" })

      assert result["isError"]
      assert_equal "rate_limited: Too many requests. Try again later.", text(result)
    end
  end

  test "the exchange unavailable: a generic tool error" do
    @api_transport.define_singleton_method(:call) { |*| [ 503, "" ] }

    result = call_tool("listProjects")

    assert result["isError"]
    assert_equal "Goalner is unavailable. Try again later.", text(result)
  end

  test "a wrong service key is refused like an ended connection" do
    @app = build_app(service_key: "wrong")

    assert_equal 401, mcp_request("tools/call", { name: "listProjects", arguments: {} }).status
  end

  test "personal tokens are sent as they are, without an exchange" do
    call_tool("listProjects", token: "glnr_two_goal_read")

    assert_equal 0, exchanges
  end
end
