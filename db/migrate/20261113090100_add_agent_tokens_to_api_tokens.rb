# Agent tokens (spec agents, "Issue agent tokens"; add-agents design.md,
# decision 5): API tokens whose user is an agent, issued by a person. They
# name no project and no MCP connection, and say where they work. A row is
# now exactly one of three kinds. (channels IS NOT NULL is spelled out: a
# CHECK passes when its expression is NULL, as NULL IN (...) is.)
#
# expires_at stays NOT NULL for every kind: an agent token is issued for
# ApiToken::AGENT_LIFETIME, 100 years, so no code path meets a token without
# an expiry.
class AddAgentTokensToApiTokens < ActiveRecord::Migration[8.1]
  def up
    add_reference :api_tokens, :issuer, foreign_key: { to_table: :users }
    add_column :api_tokens, :channels, :string
    remove_check_constraint :api_tokens, name: "api_tokens_project_or_connection"
    add_check_constraint :api_tokens, <<~SQL.squish, name: "api_tokens_kind"
      (project_id IS NOT NULL AND oauth_access_token_id IS NULL AND issuer_id IS NULL AND channels IS NULL)
      OR (project_id IS NULL AND oauth_access_token_id IS NOT NULL AND issuer_id IS NULL AND channels IS NULL)
      OR (project_id IS NULL AND oauth_access_token_id IS NULL AND issuer_id IS NOT NULL
        AND channels IS NOT NULL AND channels IN ('api', 'mcp', 'api_mcp'))
    SQL
  end

  # Agent tokens cannot exist without these columns, so they are deleted:
  # their agents need new ones issued once this is migrated again.
  def down
    execute "DELETE FROM api_tokens WHERE issuer_id IS NOT NULL"
    remove_check_constraint :api_tokens, name: "api_tokens_kind"
    add_check_constraint :api_tokens, "(project_id IS NULL) <> (oauth_access_token_id IS NULL)", name: "api_tokens_project_or_connection"
    remove_column :api_tokens, :channels
    remove_reference :api_tokens, :issuer, foreign_key: { to_table: :users }
  end
end
