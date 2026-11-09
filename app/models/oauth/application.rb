# An MCP client (spec mcp-authorization; add-mcp-oauth design.md, decisions
# 1, 4 and 5): always public, registered by a client ID metadata document
# ("cimd", whose uid is the document's URL) or by dynamic registration ("dcr").
class Oauth::Application < ApplicationRecord
  include ::Doorkeeper::Orm::ActiveRecord::Mixins::Application

  enum :registration, { cimd: "cimd", dcr: "dcr" }, validate: true

  def redirect_uris
    redirect_uri.to_s.split
  end

  # Only an app on the user's own device can receive the code.
  def loopback_only?
    redirect_uris.all? { |uri| Oauth.loopback_host?(URI(uri).host) }
  rescue URI::InvalidURIError
    false
  end

  # The host the client says it redirects to, for the connections list.
  def redirect_host
    URI(redirect_uris.first.to_s).host
  rescue URI::InvalidURIError
    nil
  end
end
