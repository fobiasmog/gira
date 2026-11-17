# Changes replace sprints, milestones and OpenSpec changes (spec changes;
# replace-sprints-with-changes design.md, decisions 1 to 3 and 7). Each
# OpenSpec change becomes a change with its tasks; sprints and milestones are
# dropped, so their other tasks end up in no change.
class ReplaceSprintsWithChanges < ActiveRecord::Migration[8.1]
  def up
    create_table :changes do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.datetime :archived_at
      t.text :tasks_text
      t.references :imported_by, foreign_key: { to_table: :users }
      t.datetime :imported_at
      t.timestamps
    end
    add_index :changes, %i[project_id name], unique: true, where: "archived_at IS NULL", name: "index_changes_on_project_id_and_name_open"

    add_reference :tasks, :change, foreign_key: true
    add_column :tasks, :in_tasks_md, :boolean, null: false, default: false

    execute <<~SQL.squish
      INSERT INTO changes (project_id, name, tasks_text, imported_by_id, imported_at, created_at, updated_at)
      SELECT project_id, name, tasks_text, imported_by_id, imported_at, created_at, updated_at
      FROM openspec_changes ORDER BY id
    SQL

    execute <<~SQL.squish
      UPDATE tasks SET change_id = changes.id, in_tasks_md = TRUE
      FROM openspec_changes
      JOIN changes ON changes.project_id = openspec_changes.project_id AND changes.name = openspec_changes.name
      WHERE tasks.openspec_change_id = openspec_changes.id
    SQL

    # Subtasks added by hand to an imported card take their card's change.
    execute <<~SQL.squish
      UPDATE tasks SET change_id = parents.change_id
      FROM tasks parents
      WHERE tasks.parent_id = parents.id AND tasks.change_id IS NULL AND parents.change_id IS NOT NULL
    SQL

    # The list scope now merges tasks that were in different sprints.
    execute <<~SQL.squish
      UPDATE tasks SET position = numbered.new_position
      FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY project_id, status_id, change_id, parent_id ORDER BY position, id) - 1 AS new_position
        FROM tasks WHERE archived_at IS NULL AND position IS NOT NULL
      ) numbered
      WHERE tasks.id = numbered.id
    SQL

    remove_reference :tasks, :sprint, foreign_key: true, index: true
    remove_reference :tasks, :milestone, foreign_key: true, index: true
    remove_reference :tasks, :origin_task, foreign_key: { to_table: :tasks, on_delete: :nullify }, index: true
    remove_reference :tasks, :openspec_change, foreign_key: true, index: true
    drop_table :openspec_changes
    drop_table :sprints
    drop_table :milestones
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
