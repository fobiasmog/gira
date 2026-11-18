# The agent of a change, its block, releases in the history and agents'
# check-ins (spec change-requests; add-change-requests design.md, decisions
# 2, 4, 9 and 13).
#
# - changes.agent_id is the agent's user: picked while agent_taken_at is
#   null, on the change once it is set. An agent is on at most one open
#   change, in any project, which the partial unique index backs; an archived
#   change keeps its agent as a record.
# - changes.agent_blocked_at is set while the agent's context is full.
# - change_events gains release and block entries; a release names the
#   released agent.
# - memberships.checked_in_at is an agent's last take in the project.
class AddAgentsToChanges < ActiveRecord::Migration[8.1]
  PHASES = "'idea', 'exploring', 'proposed', 'implementing'"
  OLD_EVENT_KINDS = "(kind = 'phase' AND phase IN (#{PHASES}) AND paths IS NULL) OR (kind = 'import' AND phase IS NULL AND paths IS NOT NULL)"
  EVENT_KINDS = <<~SQL.squish
    (kind = 'phase' AND phase IN (#{PHASES}) AND paths IS NULL AND agent_id IS NULL)
    OR (kind = 'import' AND phase IS NULL AND paths IS NOT NULL AND agent_id IS NULL)
    OR (kind = 'release' AND phase IS NULL AND paths IS NULL AND agent_id IS NOT NULL)
    OR (kind = 'block' AND phase IS NULL AND paths IS NULL AND agent_id IS NULL)
  SQL

  def change
    add_reference :changes, :agent, foreign_key: { to_table: :users }
    add_column :changes, :agent_taken_at, :datetime
    add_column :changes, :agent_blocked_at, :datetime
    add_index :changes, :agent_id, unique: true, where: "agent_taken_at IS NOT NULL AND archived_at IS NULL", name: "index_changes_on_agent_id_on"
    add_check_constraint :changes,
      "(agent_taken_at IS NULL OR agent_id IS NOT NULL) AND (agent_blocked_at IS NULL OR agent_taken_at IS NOT NULL)",
      name: "changes_agent"

    add_reference :change_events, :agent, foreign_key: { to_table: :users }, index: false
    remove_check_constraint :change_events, OLD_EVENT_KINDS, name: "change_events_kind"
    add_check_constraint :change_events, EVENT_KINDS, name: "change_events_kind"

    add_column :memberships, :checked_in_at, :datetime
  end
end
