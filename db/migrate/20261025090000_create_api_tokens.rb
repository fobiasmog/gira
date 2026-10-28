# Personal API tokens (spec api-tokens). Only a SHA-256 digest of each value
# is stored, with its last four characters so the owner can tell tokens apart.
class CreateApiTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.string :access, null: false
      t.string :token_digest, null: false, index: { unique: true }
      t.string :last_characters, null: false
      t.datetime :expires_at, null: false, index: true
      t.datetime :last_used_at
      t.timestamps
    end
  end
end
