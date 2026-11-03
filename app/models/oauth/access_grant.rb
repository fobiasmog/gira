# Doorkeeper's authorization code, usable once within 10 minutes (spec
# mcp-authorization, "Consent decision"). Stored as a digest, with its PKCE
# challenge.
class Oauth::AccessGrant < ApplicationRecord
  include ::Doorkeeper::Orm::ActiveRecord::Mixins::AccessGrant

  belongs_to :resource_owner, class_name: "User"
end
