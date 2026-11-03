# Goalner as the OAuth 2.1 authorization server of its MCP server (spec
# mcp-authorization; add-mcp-oauth design.md). Doorkeeper does the protocol
# (config/initializers/doorkeeper.rb); this namespace holds what it lacks.
module Oauth
  SCOPES = %w[read write].freeze

  # The issuer: the application's origin, as the MCP server names it in its
  # protected resource metadata (MCP_ISSUER there).
  def self.issuer
    Rails.configuration.x.oauth.issuer
  end

  # The one resource access tokens are issued for: the MCP endpoint's URL
  # (MCP_RESOURCE_URL), which is also their audience.
  def self.resource
    Rails.configuration.x.oauth.resource
  end

  # Loopback redirect URIs, which match on any port (RFC 8252, 7.3). Only
  # literal loopback addresses and "localhost" count, never other names.
  def self.loopback_host?(host)
    host = host.to_s.downcase.delete_prefix("[").delete_suffix("]")
    host == "localhost" || IPAddr.new(host).loopback?
  rescue IPAddr::Error
    false
  end

  # A redirect URI clients may register: HTTPS, or HTTP on a loopback host,
  # absolute, with a host and without userinfo or a fragment (design.md,
  # decisions 4 and 5).
  def self.allowed_redirect_uri?(value)
    return false unless value.is_a?(String) && value.length <= 2048

    uri = URI.parse(value)
    return false unless uri.host.present? && uri.userinfo.nil? && uri.fragment.nil?

    uri.scheme == "https" || (uri.scheme == "http" && loopback_host?(uri.host))
  rescue URI::InvalidURIError
    false
  end
end
