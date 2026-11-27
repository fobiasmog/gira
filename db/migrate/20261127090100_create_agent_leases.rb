# Leases of agents to runners, and their run tokens (spec agent-runners;
# add-runners-and-workspaces design.md, decision 2).
#
# - agent_leases.agent_id is the agent's user, as changes.agent_id is. An
#   agent has at most one lease that has not ended, which the partial unique
#   index backs; a lease that has lapsed is ended lazily.
# - A run token is an agent token with agent_lease_id set: the constraint
#   allows the column on agent tokens only. A lease has at most one.
class CreateAgentLeases < ActiveRecord::Migration[8.1]
  OLD_KINDS = <<~SQL.squish
    (project_id IS NOT NULL AND oauth_access_token_id IS NULL AND issuer_id IS NULL AND channels IS NULL)
    OR (project_id IS NULL AND oauth_access_token_id IS NOT NULL AND issuer_id IS NULL AND channels IS NULL)
    OR (project_id IS NULL AND oauth_access_token_id IS NULL AND issuer_id IS NOT NULL
      AND channels IS NOT NULL AND channels IN ('api', 'mcp', 'api_mcp'))
  SQL
  KINDS = <<~SQL.squish
    (project_id IS NOT NULL AND oauth_access_token_id IS NULL AND issuer_id IS NULL AND channels IS NULL AND agent_lease_id IS NULL)
    OR (project_id IS NULL AND oauth_access_token_id IS NOT NULL AND issuer_id IS NULL AND channels IS NULL AND agent_lease_id IS NULL)
    OR (project_id IS NULL AND oauth_access_token_id IS NULL AND issuer_id IS NOT NULL
      AND channels IS NOT NULL AND channels IN ('api', 'mcp', 'api_mcp'))
  SQL

  def up
    create_table :agent_leases do |t|
      t.references :agent, null: false, foreign_key: { to_table: :users }, index: false
      t.references :runner, null: false, foreign_key: true
      t.datetime :renewed_at, null: false
      t.datetime :ended_at
      t.timestamps
    end
    add_index :agent_leases, :agent_id
    add_index :agent_leases, :agent_id, unique: true, where: "ended_at IS NULL", name: "index_agent_leases_live"

    add_reference :api_tokens, :agent_lease, foreign_key: true, index: { unique: true }
    remove_check_constraint :api_tokens, name: "api_tokens_kind"
    add_check_constraint :api_tokens, KINDS, name: "api_tokens_kind"
  end

  # Run tokens cannot exist without their leases, so they are deleted.
  def down
    execute "DELETE FROM api_tokens WHERE agent_lease_id IS NOT NULL"
    remove_check_constraint :api_tokens, name: "api_tokens_kind"
    add_check_constraint :api_tokens, OLD_KINDS, name: "api_tokens_kind"
    remove_reference :api_tokens, :agent_lease, foreign_key: true, index: { unique: true }
    drop_table :agent_leases
  end
end
