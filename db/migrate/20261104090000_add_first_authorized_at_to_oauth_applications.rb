# When an MCP client was first authorized (harden-mcp-oauth design.md,
# decision 8), so housekeeping keeps a dynamically registered client that was
# ever authorized after its codes and tokens are purged. Backfilled from the
# earliest code or access token of each client still on record.
class AddFirstAuthorizedAtToOauthApplications < ActiveRecord::Migration[8.1]
  def up
    add_column :oauth_applications, :first_authorized_at, :datetime

    execute <<~SQL
      UPDATE oauth_applications SET first_authorized_at = earliest.created_at
      FROM (
        SELECT application_id, MIN(created_at) AS created_at FROM (
          SELECT application_id, created_at FROM oauth_access_grants
          UNION ALL
          SELECT application_id, created_at FROM oauth_access_tokens
        ) AS authorizations
        GROUP BY application_id
      ) AS earliest
      WHERE earliest.application_id = oauth_applications.id
    SQL
  end

  def down
    remove_column :oauth_applications, :first_authorized_at
  end
end
