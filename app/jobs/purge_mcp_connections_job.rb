# Housekeeping for MCP connections (spec mcp-authorization, "Connection
# lifetime" and "Dynamic client registration"; add-mcp-oauth design.md,
# decision 10). Scheduled daily in config/recurring.yml.
#
# - Ends connections whose newest access token is older than 90 days.
# - Deletes dynamically registered clients never authorized within 24 hours
#   of registering. One authorized once is kept, even after its codes and
#   tokens are gone (harden-mcp-oauth design.md, decision 8).
# - Deletes CIMD clients with no tokens or codes for 90 days.
# - Deletes access tokens revoked more than 30 days ago, with their
#   connection tokens. Expired access tokens that were never revoked are
#   kept: their row also holds the refresh token, so deleting it would end
#   the connection early.
# - Deletes codes created more than 30 days ago, which covers those revoked
#   since: a code lives 10 minutes, so these were redeemed, revoked or left.
class PurgeMcpConnectionsJob < ApplicationJob
  UNUSED_FOR = 90.days
  UNAUTHORIZED_CLIENT_KEPT_FOR = 24.hours
  REVOKED_KEPT_FOR = 30.days

  def perform
    end_unused_connections
    delete_unauthorized_clients
    delete_unused_metadata_document_clients
    delete_revoked
  end

  private
    def end_unused_connections
      Oauth::AccessToken.group(:resource_owner_id, :application_id)
        .having("MAX(created_at) < ? AND COUNT(*) FILTER (WHERE revoked_at IS NULL) > 0", UNUSED_FOR.ago)
        .pluck(:resource_owner_id, :application_id).each do |user_id, application_id|
          McpConnection.revoke User.find(user_id), Oauth::AccessToken.where(resource_owner_id: user_id, application_id: application_id),
            Oauth::AccessGrant.where(resource_owner_id: user_id, application_id: application_id)
        end
    end

    def delete_unauthorized_clients
      Oauth::Application.dcr.where(first_authorized_at: nil, created_at: ...UNAUTHORIZED_CLIENT_KEPT_FOR.ago).in_batches.delete_all
    end

    def delete_unused_metadata_document_clients
      cutoff = UNUSED_FOR.ago
      Oauth::Application.cimd.where(created_at: ...cutoff)
        .where.not(id: Oauth::AccessGrant.where(created_at: cutoff..).select(:application_id))
        .where.not(id: Oauth::AccessToken.where(created_at: cutoff..).select(:application_id))
        .in_batches.delete_all
    end

    # Connection tokens go with their access tokens (on delete cascade).
    def delete_revoked
      Oauth::AccessToken.where(revoked_at: ...REVOKED_KEPT_FOR.ago).in_batches.delete_all
      Oauth::AccessGrant.where(created_at: ...REVOKED_KEPT_FOR.ago).in_batches.delete_all
    end
end
