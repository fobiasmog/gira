# The workspace of a change (spec agent-workspaces; add-runners-and-workspaces
# design.md, decision 3): where a runner keeps the change's worktree, on
# which branch, cut from which base branch, and its latest checkpoint. A
# change has at most one. The three checkpoint columns are set together.
class CreateWorkspaces < ActiveRecord::Migration[8.1]
  def change
    create_table :workspaces do |t|
      t.references :change, null: false, foreign_key: true, index: { unique: true }
      t.references :runner, null: false, foreign_key: true
      t.text :path, null: false
      t.string :branch, null: false
      t.string :base_branch, null: false
      t.string :state, null: false, default: "active"
      t.string :head_commit
      t.boolean :uncommitted
      t.datetime :checkpoint_at
      t.timestamps
    end
    add_check_constraint :workspaces, "state IN ('active', 'kept', 'removed')", name: "workspaces_state"
    add_check_constraint :workspaces,
      "(head_commit IS NULL) = (checkpoint_at IS NULL) AND (uncommitted IS NULL) = (checkpoint_at IS NULL)",
      name: "workspaces_checkpoint"
  end
end
