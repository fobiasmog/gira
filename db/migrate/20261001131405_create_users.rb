class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.datetime :confirmed_at
      t.integer :failed_login_attempts, null: false, default: 0
      t.datetime :locked_until
      t.string :name, null: false
      t.string :lang, null: false, default: "en"
      t.jsonb :contact_links, null: false, default: {}
      t.boolean :admin, null: false, default: false

      t.timestamps
    end
    add_index :users, :email_address, unique: true
  end
end
