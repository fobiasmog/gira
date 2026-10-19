class CreateProjectsAndBoard < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :title, null: false
      t.string :short_name, null: false
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.integer :last_task_number, null: false, default: 0
      t.datetime :archived_at
      t.timestamps
    end

    create_table :memberships do |t|
      t.references :project, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :memberships, %i[project_id user_id], unique: true

    create_table :statuses do |t|
      t.references :project, null: false, foreign_key: true
      t.string :title, null: false
      t.string :color
      t.integer :position, null: false
      t.boolean :done, null: false, default: false
      t.timestamps
    end
    add_index :statuses, :project_id, unique: true, where: "done", name: "index_statuses_one_done_per_project"

    create_table :invitations do |t|
      t.references :project, null: false, foreign_key: true, index: false
      t.references :inviter, null: false, foreign_key: { to_table: :users }
      t.string :email, null: false
      t.string :token_digest, null: false, index: { unique: true }
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :invitations, "project_id, lower(email)", unique: true,
      where: "accepted_at IS NULL AND revoked_at IS NULL", name: "index_invitations_one_pending_per_email"

    create_table :sprints do |t|
      t.references :project, null: false, foreign_key: true
      t.string :title, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.boolean :active, null: false, default: false
      t.datetime :archived_at
      t.timestamps
    end
    add_index :sprints, :project_id, unique: true, where: "active", name: "index_sprints_one_active_per_project"

    create_table :milestones do |t|
      t.references :project, null: false, foreign_key: true
      t.string :title, null: false
      t.datetime :deleted_at
      t.timestamps
    end

    create_table :labels do |t|
      t.references :project, null: false, foreign_key: true, index: false
      t.string :title, null: false
      t.timestamps
    end
    add_index :labels, "project_id, lower(title)", unique: true, name: "index_labels_unique_title_per_project"
  end
end
