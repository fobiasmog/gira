# Doorkeeper's access token, for one MCP connection (spec mcp-authorization).
# The row also holds the refresh token. Both are stored as digests; the
# access token itself is a JWT (Oauth::JwtGenerator).
class Oauth::AccessToken < ApplicationRecord
  include ::Doorkeeper::Orm::ActiveRecord::Mixins::AccessToken

  belongs_to :resource_owner, class_name: "User"
end
