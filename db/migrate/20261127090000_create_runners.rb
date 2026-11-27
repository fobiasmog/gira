# Runners (spec agent-runners; add-runners-and-workspaces design.md, decision
# 1): a machine's credential, owned by a person, kept apart from api_tokens so
# that no rule about tokens applies to it by accident. Only a SHA-256 digest
# of the secret is stored. A runner is never deleted, since leases and
# workspaces name it: revoking sets revoked_at, and rotating replaces the
# digest.
class CreateRunners < ActiveRecord::Migration[8.1]
  def change
    create_table :runners do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :last_characters, null: false
      t.datetime :last_contact_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :runners, :token_digest, unique: true
  end
end
