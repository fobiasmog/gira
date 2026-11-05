require "test_helper"

# A refresh and a disconnect of one connection at the same time (spec
# mcp-authorization, "Connection lifetime", "Disconnected during a refresh";
# harden-mcp-oauth design.md, decision 2). Each runs in its own thread with
# its own database connection, so the test runs outside a transaction and
# deletes what it created.
class McpConnectionRaceTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    @user = users(:two)
    @client = oauth_applications(:cursor)
    access_token = Oauth::AccessToken.create!(application: @client, resource_owner_id: @user.id, scopes: "read",
      expires_in: 1.hour.to_i, use_refresh_token: true)
    @refresh_token = access_token.plaintext_refresh_token
  end

  teardown do
    restore_token_creation
    Oauth::AccessToken.where(resource_owner_id: @user.id).delete_all
    Oauth::AccessGrant.where(resource_owner_id: @user.id).delete_all
  end

  # Holds every new access token until go is given, once inside is signaled.
  def hold_token_creation(inside, go)
    original = Oauth::AccessToken.method(:create_for)
    Oauth::AccessToken.define_singleton_method(:create_for) do |**attributes|
      inside << true
      go.pop(timeout: 10)
      original.call(**attributes)
    end
  end

  def restore_token_creation
    Oauth::AccessToken.singleton_class.remove_method(:create_for) if Oauth::AccessToken.singleton_class.method_defined?(:create_for, false)
  end

  def refresh_in_thread(refresh_token)
    Thread.new do
      session = open_session
      session.post oauth_token_path, params: { grant_type: "refresh_token", refresh_token: refresh_token, client_id: @client.uid }
      session.response.parsed_body
    end
  end

  def disconnect
    ActiveRecord::Base.connection_pool.with_connection { McpConnection.find(@user, @client.id).disconnect! }
  end

  # Until thread finishes or waits for a row lock in this database. The
  # query cache would answer the same count every time.
  def wait_for_lock_or_end(thread)
    100.times do
      waiting = ActiveRecord::Base.uncached do
        ActiveRecord::Base.connection.select_value(<<~SQL)
          SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock'
        SQL
      end
      return if !thread.alive? || waiting.positive?

      sleep 0.05
    end
    flunk "the thread neither finished nor waited for a lock"
  end

  test "the refresh holds the lock: its new tokens are revoked by the disconnect" do
    inside, go = Queue.new, Queue.new
    hold_token_creation(inside, go)
    refresh = refresh_in_thread(@refresh_token)
    assert inside.pop(timeout: 10), "the refresh reached the token's creation"

    disconnecting = Thread.new { disconnect }
    wait_for_lock_or_end(disconnecting)
    go << true
    tokens = refresh.value
    disconnecting.join

    assert tokens["access_token"], tokens.inspect
    assert Oauth::AccessToken.by_token(tokens["access_token"]).revoked?, "the new access token ended with the connection"
    assert_empty McpConnection.for(@user)
    restore_token_creation
    assert_equal "invalid_grant", refresh(tokens["refresh_token"], @client)["error"]
  end

  test "the disconnect holds the lock: the refresh gets invalid_grant" do
    inside, go = Queue.new, Queue.new
    disconnecting = Thread.new do
      ApplicationRecord.transaction do
        disconnect
        inside << true
        go.pop(timeout: 10)
      end
    end
    assert inside.pop(timeout: 10), "the disconnect revoked"

    refresh = refresh_in_thread(@refresh_token)
    wait_for_lock_or_end(refresh)
    go << true
    disconnecting.join

    assert_equal "invalid_grant", refresh.value["error"]
    assert_empty McpConnection.for(@user)
    assert_equal 1, Oauth::AccessToken.where(resource_owner_id: @user.id).count, "no token was issued"
  end
end
