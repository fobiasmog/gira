class CreateTasksAndComments < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      t.references :project, null: false, foreign_key: true, index: false
      t.integer :number, null: false
      t.string :title, null: false
      t.text :description, null: false, default: ""
      t.references :creator, null: false, foreign_key: { to_table: :users }
      t.references :assignee, foreign_key: { to_table: :users }
      t.references :status, foreign_key: true # null: in the backlog
      t.integer :position
      t.references :parent, foreign_key: { to_table: :tasks }
      t.references :sprint, foreign_key: true
      t.references :milestone, foreign_key: true
      t.references :label, foreign_key: { on_delete: :nullify }
      t.references :origin_task, foreign_key: { to_table: :tasks, on_delete: :nullify }
      t.datetime :deadline
      t.boolean :important, null: false, default: false
      t.datetime :completed_at
      t.datetime :archived_at
      t.timestamps
    end
    add_index :tasks, %i[project_id number], unique: true

    create_table :comments do |t|
      t.references :task, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.datetime :deleted_at
      t.timestamps
    end

    create_table :announcements do |t|
      t.text :body, null: false
      t.boolean :welcome, null: false, default: false
      t.timestamps
    end

    create_table :announcement_dismissals do |t|
      t.references :announcement, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :announcement_dismissals, %i[announcement_id user_id], unique: true
  end
end
