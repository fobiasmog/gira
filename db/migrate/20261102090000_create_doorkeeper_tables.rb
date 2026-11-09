# Doorkeeper's tables for MCP connections (spec mcp-authorization;
# add-mcp-oauth design.md, decision 1), as its 5.9 generators write them with
# the PKCE columns, for public clients only:
#
# - applications have no secret, and record how they registered: a client ID
#   metadata document ("cimd", whose uid is the document's URL) or dynamic
#   registration ("dcr"), and when the document was last fetched;
# - tokens and grants store SHA-256 digests (hash_token_secrets), and the
#   access token column holds the digest of a JWT;
# - previous_refresh_token makes Doorkeeper revoke a refresh token only once
#   the access token that replaced it is first used.
#
# Rows go with their user and application.
class CreateDoorkeeperTables < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_applications do |t|
      t.string :name, null: false
      t.string :uid, null: false, index: { unique: true }
      t.string :secret
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ""
      t.boolean :confidential, null: false, default: false
      t.string :registration, null: false
      t.datetime :metadata_fetched_at
      t.timestamps

      t.check_constraint "registration IN ('cimd', 'dcr')", name: "oauth_applications_registration"
    end

    create_table :oauth_access_grants do |t|
      t.references :resource_owner, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :application, null: false, foreign_key: { to_table: :oauth_applications, on_delete: :cascade }
      t.string :token, null: false, index: { unique: true }
      t.integer :expires_in, null: false
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ""
      t.string :code_challenge
      t.string :code_challenge_method
      t.datetime :created_at, null: false
      t.datetime :revoked_at
    end

    create_table :oauth_access_tokens do |t|
      t.references :resource_owner, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :application, null: false, foreign_key: { to_table: :oauth_applications, on_delete: :cascade }
      t.string :token, null: false, index: { unique: true }
      t.string :refresh_token, index: { unique: true }
      t.integer :expires_in
      t.string :scopes
      t.datetime :created_at, null: false
      t.datetime :revoked_at
      t.string :previous_refresh_token, null: false, default: ""
    end
  end
end
