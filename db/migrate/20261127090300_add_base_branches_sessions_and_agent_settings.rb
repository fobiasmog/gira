# The base branch of a change, which is main for every change for now (spec
# changes, "Base branch of a change"; add-runners-and-workspaces design.md,
# decision 8); the session of the agent's stint on it (spec agent-workspaces,
# "Session of a stint"; decision 3), which only an agent on the change has;
# and an agent's model and instructions (spec agents, "Agent settings").
class AddBaseBranchesSessionsAndAgentSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :changes, :base_branch, :string, null: false, default: "main"
    add_column :changes, :agent_session_id, :uuid
    add_check_constraint :changes, "agent_session_id IS NULL OR agent_taken_at IS NOT NULL", name: "changes_agent_session"

    add_column :agents, :model, :string
    add_column :agents, :instructions, :text
  end
end
