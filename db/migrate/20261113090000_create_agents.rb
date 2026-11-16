# Agents (spec agents; add-agents design.md, decision 1). An agent is a users
# row, so it can be a member, an assignee, a creator and an author like anyone
# else, with a row here that marks it as an agent, records who created it and
# holds its soft deletion.
class CreateAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :agents do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.datetime :deleted_at
      t.timestamps
    end
  end
end
