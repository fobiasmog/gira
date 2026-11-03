# Connection tokens (spec api-tokens, "Connection tokens"; add-mcp-oauth
# design.md, decision 8): API tokens issued to the MCP server for an MCP
# connection's access token instead of for a project. A row names exactly one
# of the two, and goes with its access token. Existing rows all have a project.
class AddConnectionTokensToApiTokens < ActiveRecord::Migration[8.1]
  def up
    change_column_null :api_tokens, :project_id, true
    add_reference :api_tokens, :oauth_access_token, foreign_key: { on_delete: :cascade }
    add_check_constraint :api_tokens, "(project_id IS NULL) <> (oauth_access_token_id IS NULL)", name: "api_tokens_project_or_connection"
  end

  # Connection tokens live for an hour at most, and the MCP server exchanges
  # again for new ones, so they are deleted rather than kept.
  def down
    execute "DELETE FROM api_tokens WHERE project_id IS NULL"
    remove_check_constraint :api_tokens, name: "api_tokens_project_or_connection"
    remove_reference :api_tokens, :oauth_access_token, foreign_key: true
    change_column_null :api_tokens, :project_id, false
  end
end
