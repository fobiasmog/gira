require "test_helper"

# Spec mcp-authorization, "Connection lifetime" ("Unused") and "Dynamic
# client registration" ("Unused client"); add-mcp-oauth design.md, decision 10.
class PurgeMcpConnectionsJobTest < ActionDispatch::IntegrationTest
  SERVICE_KEY = { "X-Goalner-Service-Key" => "development-mcp-service-key" }.freeze

  setup do
    @claude = oauth_applications(:claude_ai)
  end

  def purge
    PurgeMcpConnectionsJob.perform_now
  end

  def connections(user = users(:two))
    McpConnection.for(user)
  end

  def exchange(access_token)
    post internal_mcp_tokens_path, params: { access_token: access_token }, headers: SERVICE_KEY
    response
  end

  test "unused: a connection not used for 90 days ends and leaves the connected apps" do
    tokens = connect(users(:two), @claude)
    travel 90.days + 1.minute

    purge

    assert_empty connections
    assert_equal "invalid_grant", refresh(tokens["refresh_token"], @claude)["error"]
  end

  test "a connection used within 90 days is kept, and its expired, unrevoked token still refreshes" do
    tokens = connect(users(:two), @claude)
    travel 89.days

    purge

    assert_equal 1, connections.size
    assert Oauth::AccessToken.by_refresh_token(tokens["refresh_token"]).expired?
    refreshed = refresh(tokens["refresh_token"], @claude)
    assert refreshed["access_token"], refreshed.inspect
    assert_equal 201, exchange(refreshed["access_token"]).status
  end

  test "only the unused connection of a user ends" do
    old = connect(users(:two), @claude)
    travel 80.days
    oauth_applications(:claude_code).update!(metadata_fetched_at: Time.current) # refetched, without the network
    recent = connect(users(:two), oauth_applications(:claude_code))
    travel 11.days

    purge

    assert_equal [ "Claude Code" ], connections.map(&:client_name)
    assert_equal "invalid_grant", refresh(old["refresh_token"], @claude)["error"]
    assert refresh(recent["refresh_token"], oauth_applications(:claude_code))["access_token"]
  end

  test "unused client: a registered client without any authorization within 24 hours is deleted" do
    unused = Oauth::Application.create!(name: "Unused", redirect_uri: "https://unused.example/cb", registration: :dcr)
    used = Oauth::Application.create!(name: "Used", redirect_uri: "https://used.example/cb", registration: :dcr)
    connect(users(:two), used)
    travel 23.hours
    purge
    assert Oauth::Application.exists?(unused.id)

    travel 2.hours
    purge

    assert_not Oauth::Application.exists?(unused.id)
    assert Oauth::Application.exists?(used.id)
  end

  # Spec mcp-authorization, "Authorized client kept"; harden-mcp-oauth
  # design.md, decision 8. The job runs daily: once the rows are gone, the
  # next run would have taken the client for one never authorized.
  test "authorized client kept: after a disconnect and 60 days, the same client id gets the consent page" do
    client = oauth_applications(:cursor)
    connect(users(:two), client)
    McpConnection.find(users(:two), client.id).disconnect!
    travel 31.days
    purge
    travel 29.days
    purge

    assert_empty Oauth::AccessToken.where(application: client)
    sign_in_as users(:two)
    get oauth_authorization_path(authorization_params(client))
    assert_response :success
    assert_select "h1", /wants to access your Goalner account/
  end

  test "an unredeemed code is deleted after 30 days, and its client counts as authorized" do
    client = Oauth::Application.create!(name: "Approved once", redirect_uri: "https://approved.example/cb", registration: :dcr)
    sign_in_as users(:two)
    approve(authorization_params(client))
    assert_in_delta Time.current, client.reload.first_authorized_at, 1

    travel 29.days
    purge
    assert_equal 1, Oauth::AccessGrant.where(application: client).count

    travel 2.days
    purge
    assert_empty Oauth::AccessGrant.where(application: client)
    travel 1.day
    purge
    assert Oauth::Application.exists?(client.id)
  end

  test "the first authorization is kept when later ones come" do
    client = oauth_applications(:cursor)
    sign_in_as users(:two)
    approve(authorization_params(client))
    first = client.reload.first_authorized_at
    travel 1.day
    approve(authorization_params(client))

    assert_equal first, client.reload.first_authorized_at
  end

  test "a registered client whose codes were purged keeps its live connection" do
    client = Oauth::Application.create!(name: "Cursor", redirect_uri: "https://cursor.example/cb", registration: :dcr)
    tokens = connect(users(:two), client)
    travel 31.days
    tokens = refresh(tokens["refresh_token"], client)
    exchange(tokens["access_token"])

    purge

    assert_empty Oauth::AccessGrant.where(application: client)
    assert Oauth::Application.exists?(client.id)
    assert refresh(tokens["refresh_token"], client)["access_token"]
  end

  test "CIMD clients without tokens or codes for 90 days are deleted" do
    fetched = Oauth::Application.create!(name: "Fetched", uid: "https://fetched.example/metadata", redirect_uri: "https://fetched.example/cb",
      registration: :cimd, metadata_fetched_at: Time.current)
    connect(users(:two), @claude)
    travel 91.days
    recent = Oauth::Application.create!(name: "Recent", uid: "https://recent.example/metadata", redirect_uri: "https://recent.example/cb",
      registration: :cimd, metadata_fetched_at: Time.current)

    purge

    assert_not Oauth::Application.exists?(fetched.id)
    assert_not Oauth::Application.exists?(@claude.id), "its connection ended unused, so nothing is left"
    assert Oauth::Application.exists?(recent.id)
  end

  test "a CIMD client in use is kept" do
    tokens = connect(users(:two), @claude)
    travel 60.days
    refresh(tokens["refresh_token"], @claude)
    travel 31.days

    purge

    assert Oauth::Application.exists?(@claude.id)
    assert_equal 1, connections.size
  end

  test "revoked rows older than 30 days are deleted with their connection tokens; newer ones are kept" do
    tokens = connect(users(:two), @claude)
    connection_token = exchange(tokens["access_token"]).parsed_body["token"]
    McpConnection.find(users(:two), @claude.id).disconnect!
    ApiToken.issue_for_connection!(Oauth::AccessToken.sole) # a connection token left behind by a race
    travel 29.days
    purge
    assert_equal 1, Oauth::AccessToken.count
    assert_equal 1, Oauth::AccessGrant.count

    travel 2.days
    purge

    assert_empty Oauth::AccessToken.all
    assert_empty Oauth::AccessGrant.all
    assert_empty ApiToken.of_connections
    assert_nil ApiToken.find_active_by_value(connection_token)
  end
end
