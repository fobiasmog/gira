# No ip_address column: sessions never store IP addresses (spec user-auth, "Sessions").
class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :user_agent

      t.timestamps
    end
  end
end
