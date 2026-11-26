# OpenSpec changes (spec openspec-changes; add-openspec-changes design.md,
# decision 1). A change is found by its name within its project, groups its
# cards under a milestone, and keeps the marked tasks text it last returned.
class CreateOpenspecChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :openspec_changes do |t|
      t.references :project, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.references :milestone, null: false, foreign_key: true
      t.text :tasks_text, null: false, default: ""
      t.references :imported_by, null: false, foreign_key: { to_table: :users }
      t.datetime :imported_at, null: false
      t.timestamps
    end
    add_index :openspec_changes, %i[project_id name], unique: true
  end
end
