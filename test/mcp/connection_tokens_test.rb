require_relative "support"

# Tool calls of MCP connections: the access token is exchanged for a
# connection token, cached encrypted (spec mcp-server, "Authentication" and
# "Tool calls act as the token"; spec mcp-authorization, "Connection reach";
# add-mcp-oauth design.md, decisions 8 and 9). two is a member of goal and side.
class McpConnectionTokensTest < McpIntegrationTest
  EXCHANGE = "POST /internal/mcp_token_exchange"

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
    lifetime = ApiToken.of_connections.sole.expires_at.to_i - Time.now.to_i # 3599 or 3600, by the second

    now = lifetime - 31
    assert cache.read(cache_key)
    now = lifetime - 29
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
    Internal::McpTokenExchangesController::EXCHANGES_PER_HOUR.times { call_tool("listProjects") }

    assert_no_difference -> { Task.count } do
      result = call_tool("createTask", { project_id: @goal.id, title: "Too many" })

      assert result["isError"]
      assert_equal "rate_limited: Too many requests. Try again later.", text(result)
    end
  end

  test "the exchange unavailable: 503 with a generic message, for any request" do
    @api_transport.define_singleton_method(:call) { |*| [ 503, "" ] }

    %w[tools/list tools/call].each do |method|
      response = mcp_request(method, ({ name: "listProjects", arguments: {} } if method == "tools/call"))

      assert_equal 503, response.status, method
      assert_equal "Goalner is unavailable. Try again later.", JSON.parse(response.body).dig("error", "message")
    end
  end

  test "the API unavailable once the access token is confirmed: a generic tool error" do
    assert_not_empty mcp_result("tools/list")["tools"]
    @api_transport.define_singleton_method(:call) { |*| [ 503, "" ] }

    result = call_tool("listProjects")

    assert result["isError"]
    assert_equal "Goalner is unavailable. Try again later.", text(result)
  end

  # Spec mcp-server, "Authentication", "Service key refused"; harden-mcp-oauth
  # design.md, decision 3.
  test "service key refused: 503 without invalid_token, and the client keeps its tokens" do
    @app = build_app(service_key: "wrong")

    %w[tools/list tools/call].each do |method|
      response = mcp_request(method, ({ name: "listProjects", arguments: {} } if method == "tools/call"))

      assert_equal 503, response.status, method
      assert_equal "Goalner is unavailable. Try again later.", JSON.parse(response.body).dig("error", "message")
      assert_not_includes response.headers["www-authenticate"].to_s, "invalid_token"
    end
    assert_not Oauth::AccessToken.by_token(@jwt).revoked?
  end

  # Harden-mcp-oauth design.md, decision 1: every connection request is
  # confirmed once, and the answer is reused within the request.
  test "tools/list with an access token not seen before makes one exchange, and a later tool call none" do
    assert_not_empty mcp_result("tools/list")["tools"]
    assert_equal [ EXCHANGE ], api_requests

    call_tool("listProjects")
    assert_equal [ EXCHANGE, "GET /api/projects" ], api_requests
  end

  test "a tool call with an access token not seen before makes one exchange" do
    call_tool("listProjects")

    assert_equal [ EXCHANGE, "GET /api/projects" ], api_requests
  end

  # Spec mcp-server, "Authentication", "Ended connection, new access token".
  test "ended connection, new access token: tools/list gets 401 with invalid_token" do
    McpConnection.find(users(:two), oauth_applications(:claude_ai).id).disconnect!

    response = mcp_request("tools/list")

    assert_equal 401, response.status
    assert_includes response.headers["www-authenticate"], 'error="invalid_token"'
    assert_not_includes response.body, "listProjects"
  end

  test "the exchange rate limited: tools are still listed, and a tool call gets rate_limited after one exchange" do
    original = @api_transport.method(:call)
    @api_transport.define_singleton_method(:call) do |method, path, headers, body|
      next original.call(method, path, headers, body) unless "#{method} #{path}" == EXCHANGE

      @requests << EXCHANGE
      [ 429, JSON.generate(error: "rate_limited") ]
    end

    assert_not_empty mcp_result("tools/list")["tools"]
    assert_equal 1, exchanges

    assert_no_difference -> { Task.count } do
      result = call_tool("createTask", { project_id: @goal.id, title: "Too many" })

      assert result["isError"]
      assert_equal "rate_limited: Too many requests. Try again later.", text(result)
    end
    assert_equal 2, exchanges, "one for each request"
    assert_equal [ EXCHANGE ], api_requests.uniq
  end

  # Harden-mcp-oauth design.md, decision 3: only invalid_token means the
  # connection ended.
  test "a 401 from the exchange is Refused only for invalid_token" do
    log = StringIO.new
    GoalnerMcp.logger = Logger.new(log)

    { JSON.generate(error: "invalid_service_key") => GoalnerMcp::ApiClient::Unavailable, "" => GoalnerMcp::ApiClient::Unavailable,
      "<html>Unauthorized</html>" => GoalnerMcp::ApiClient::Unavailable,
      JSON.generate(error: "invalid_token") => GoalnerMcp::ConnectionTokens::Refused }.each do |body, error|
      api = GoalnerMcp::ApiClient.new(->(*) { [ 401, body ] })
      tokens = GoalnerMcp::ConnectionTokens.new(api, service_key: "the-service-key", cache: @cache)

      assert_raises(error, body) { tokens.token_for(Struct.new(:token).new(@jwt)) }
    end

    assert_includes log.string, "refused the MCP server's credentials"
    assert_not_includes log.string, "the-service-key"
    assert_not_includes log.string, @jwt
  ensure
    GoalnerMcp.logger = Logger.new(IO::NULL)
  end

  test "personal tokens are sent as they are, without an exchange" do
    assert_not_empty mcp_result("tools/list", token: "glnr_two_goal_read")["tools"]
    call_tool("listProjects", token: "glnr_two_goal_read")

    assert_equal 0, exchanges
  end
end
