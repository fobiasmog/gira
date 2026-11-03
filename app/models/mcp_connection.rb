# An MCP connection: one user and one client, over Doorkeeper's tables (spec
# mcp-authorization, "Connection lifetime" and "Connected apps"; add-mcp-oauth
# design.md, decision 7). It is live while the user has an unrevoked access
# token or authorization code for the client, and its id is the client's.
#
# - Connected at: when its current chain of tokens began. Each refresh adds
#   a token, and the one it replaced is revoked once the new one is used, so
#   walking back from the oldest live token through tokens revoked after
#   their successor appeared finds the first one. A token revoked before
#   that belongs to an earlier, ended connection. Rows revoked more than 30
#   days ago are purged (PurgeMcpConnectionsJob), so it is at most that old.
# - Last active: the newest token. Clients refresh about hourly while in use.
# - Access: the newest token's scope.
#
# Two devices of one user that use the same client (one CIMD document)
# share a connection, and disconnecting ends both.
class McpConnection
  attr_reader :user, :application, :connected_at, :last_active_at, :access

  delegate :id, to: :application

  def self.for(user)
    tokens = Oauth::AccessToken.where(resource_owner_id: user.id).to_a.group_by(&:application_id)
    grants = Oauth::AccessGrant.where(resource_owner_id: user.id, revoked_at: nil).to_a.reject(&:expired?).group_by(&:application_id)
    applications = Oauth::Application.where(id: tokens.keys | grants.keys).index_by(&:id)

    applications.values.filter_map do |application|
      build(user, application, tokens.fetch(application.id, []), grants.fetch(application.id, []))
    end.sort_by { |connection| [ -connection.last_active_at.to_f, connection.id ] }
  end

  def self.find(user, id)
    self.for(user).find { |connection| connection.id.to_s == id.to_s } or
      raise ActiveRecord::RecordNotFound, "no MCP connection #{id}"
  end

  # Ends every connection of user, as a password change or reset does.
  def self.end_all_for(user)
    revoke Oauth::AccessToken.where(resource_owner_id: user.id), Oauth::AccessGrant.where(resource_owner_id: user.id)
  end

  def self.build(user, application, tokens, grants)
    live = tokens.reject(&:revoked?)
    return if live.empty? && grants.empty?

    newest = (live + grants).max_by(&:created_at)
    new(user: user, application: application, connected_at: chain_start(tokens, live, grants), last_active_at: newest.created_at,
      access: newest.includes_scope?("write") ? "read_write" : "read")
  end

  def self.chain_start(tokens, live, grants)
    return grants.map(&:created_at).min if live.empty?

    start = live.map(&:created_at).min
    tokens.select(&:revoked?).sort_by(&:created_at).reverse_each do |token|
      next if token.created_at >= start
      break if token.revoked_at < start

      start = token.created_at
    end
    start
  end

  # Revokes tokens and grants, and deletes their connection tokens.
  def self.revoke(tokens, grants)
    now = Time.current
    ApplicationRecord.transaction do
      ApiToken.where(oauth_access_token_id: tokens.select(:id)).delete_all
      tokens.where(revoked_at: nil).update_all(revoked_at: now)
      grants.where(revoked_at: nil).update_all(revoked_at: now)
    end
  end

  private_class_method :build, :chain_start

  def initialize(user:, application:, connected_at:, last_active_at:, access:)
    @user = user
    @application = application
    @connected_at = connected_at
    @last_active_at = last_active_at
    @access = access
  end

  def client_name
    application.name
  end

  def redirect_host
    application.redirect_host
  end

  # Ends the connection: its access tokens (and so its refresh tokens) and
  # codes are revoked, and its connection tokens deleted, so the next tool
  # call answers 401 and the next refresh invalid_grant.
  def disconnect!
    self.class.revoke Oauth::AccessToken.where(resource_owner_id: user.id, application_id: id),
      Oauth::AccessGrant.where(resource_owner_id: user.id, application_id: id)
  end
end
