# A change's idea, phase, history, files and thread (specs changes,
# openspec-changes and comments; add-change-conversation design.md,
# decisions 1, 4, 5, 7 and 11). Changes that were imported already are being
# worked on and start in Implementing; the others start in Idea. No history
# is invented for them. Reversible while no comment belongs to a change.
class AddChangeConversation < ActiveRecord::Migration[8.1]
  PHASES = "'idea', 'exploring', 'proposed', 'implementing'"

  def change
    add_column :changes, :idea, :text
    add_column :changes, :phase, :string, null: false, default: "idea"
    add_check_constraint :changes, "phase IN (#{PHASES})", name: "changes_phase"
    reversible do |direction|
      direction.up { execute "UPDATE changes SET phase = 'implementing' WHERE tasks_text IS NOT NULL" }
    end

    create_table :change_files do |t|
      t.references :change, null: false, foreign_key: true, index: false
      t.string :path, null: false
      t.text :text, null: false
      t.timestamps
    end
    add_index :change_files, %i[change_id path], unique: true

    create_table :change_events do |t|
      t.references :change, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :kind, null: false
      t.string :phase
      t.string :paths, array: true
      t.datetime :created_at, null: false
    end
    add_check_constraint :change_events,
      "(kind = 'phase' AND phase IN (#{PHASES}) AND paths IS NULL) OR (kind = 'import' AND phase IS NULL AND paths IS NOT NULL)",
      name: "change_events_kind"

    add_reference :comments, :change, foreign_key: true
    change_column_null :comments, :task_id, true
    add_check_constraint :comments, "num_nonnulls(task_id, change_id) = 1", name: "comments_task_or_change"
  end
end
