# Doorkeeper's authorization code, usable once within 10 minutes (spec
# mcp-authorization, "Consent decision"). Stored as a digest, with its PKCE
# challenge.
#
# Each one is an authorization of its client, redeemed or not, and the first
# is recorded on the client (harden-mcp-oauth design.md, decision 8).
class Oauth::AccessGrant < ApplicationRecord
  include ::Doorkeeper::Orm::ActiveRecord::Mixins::AccessGrant

  belongs_to :resource_owner, class_name: "User"

  after_create do
    Oauth::Application.where(id: application_id, first_authorized_at: nil).update_all(first_authorized_at: created_at)
  end
end
