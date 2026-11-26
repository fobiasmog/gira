# Requests for the steps of a change (spec change-requests;
# add-change-requests design.md, decision 1). A change has at most one open
# request, waiting or taken, which the partial unique index backs. Waiting
# requests are found oldest first across a project's changes.
class CreateChangeRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :change_requests do |t|
      t.references :change, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :state, null: false, default: "waiting"
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.references :taken_by, foreign_key: { to_table: :users }
      t.references :finished_by, foreign_key: { to_table: :users }
      t.datetime :taken_at
      t.datetime :finished_at
      t.timestamps
    end
    add_check_constraint :change_requests, "kind IN ('explore', 'propose', 'implement', 'archive', 'reply')", name: "change_requests_kind"
    add_check_constraint :change_requests, "state IN ('waiting', 'taken', 'done', 'failed', 'cancelled')", name: "change_requests_state"
    add_index :change_requests, :change_id, unique: true, where: "state IN ('waiting', 'taken')", name: "index_change_requests_open"
    add_index :change_requests, %i[created_at id], where: "state = 'waiting'", name: "index_change_requests_waiting"
  end
end
