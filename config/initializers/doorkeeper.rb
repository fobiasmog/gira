# Goalner as the OAuth 2.1 authorization server for MCP clients (spec
# mcp-authorization; add-mcp-oauth design.md, decision 1).
#
# - Authorization code with S256 PKCE only, for public clients: there is no
#   client secret, no implicit flow, and no client credentials grant.
# - Access tokens are JWTs for the MCP endpoint, valid for an hour
#   (Oauth::JwtGenerator). Refresh tokens rotate: the previous one is revoked
#   once the new access token is first used at the MCP server, whatever the
#   request (Internal::McpTokenExchangesController), or the new refresh token is
#   (Oauth::TokensController; harden-mcp-oauth design.md, decision 1).
# - Tokens and codes are stored as SHA-256 digests.
# - Scopes: read, and write when the user grants read-write at consent.
# - Consent is always asked: Doorkeeper never skips it for public clients.
# - Errors redirect to the client when its redirect URI is registered, and
#   render an error page otherwise.
#
# Written by hand (app/controllers/oauth, app/models/oauth): the metadata,
# client ID metadata documents, dynamic registration, the resource and
# response mode checks, consent and the localhost port match.

Rails.application.configure do
  # The issuer and the resource come from the same variables the MCP server
  # reads, which config/deploy.yml gives both roles (harden-mcp-oauth
  # design.md, decision 9). Production requires both (RequiredSecrets).
  config.x.oauth.issuer = ENV.fetch("MCP_ISSUER") do
    { "test" => "https://goalner.com", "development" => "http://localhost:3000" }[Rails.env]
  end

  config.x.oauth.resource = ENV.fetch("MCP_RESOURCE_URL") do
    { "test" => "https://goalner.com/mcp", "development" => "http://localhost:3100/mcp" }[Rails.env]
  end

  # The MCP server's key for the connection token exchange
  # (Internal::McpTokenExchangesController). bin/mcp falls back to the same value
  # outside production.
  config.x.oauth.service_key = ENV.fetch("MCP_SERVICE_KEY") { "development-mcp-service-key" unless Rails.env.production? }

  # Client ID metadata documents are paused (harden-mcp-oauth design.md,
  # decision 12): Goalner fetches no URL a client names. The metadata does
  # not offer them, so clients register dynamically, and a client ID that is
  # an HTTPS URL gets the error page. Oauth::ClientMetadataDocument stays,
  # and the tests run it with this on.
  config.x.oauth.client_metadata_documents = false
end

Doorkeeper.configure do
  orm :active_record
  application_class "Oauth::Application"
  access_token_class "Oauth::AccessToken"
  access_grant_class "Oauth::AccessGrant"

  # Sign-in, the layout, CSRF protection, the CSP and the user's language.
  # The token and revocation endpoints use ActionController::API instead.
  base_controller "ApplicationController"

  # ApplicationController has sent visitors to sign-in by now.
  resource_owner_authenticator { Current.user }

  grant_flows %w[authorization_code]
  force_pkce
  pkce_code_challenge_methods %w[S256]
  use_refresh_token

  access_token_expires_in 1.hour
  authorization_code_expires_in 10.minutes
  access_token_generator "Oauth::JwtGenerator"
  hash_token_secrets

  default_scopes :read
  optional_scopes :write
  enforce_configured_scopes

  allow_token_introspection false
  handle_auth_errors :redirect

  # Redirect URIs are HTTPS, or HTTP on a loopback address (Oauth.allowed_redirect_uri?).
  force_ssl_in_redirect_uri { |uri| !Oauth.loopback_host?(uri.host) }
end

# Loopback redirect URIs match on any port for "localhost" too, as Doorkeeper
# already does for IP literals (RFC 8252, 7.3; spec mcp-authorization,
# "Loopback on any port"). Remove once Doorkeeper releases its #1960:
# test/integration/oauth_authorization_request_test.rb then fails.
module DoorkeeperLocalhostPorts
  def matches?(url, client_url)
    url = as_uri(url)
    client_url = as_uri(client_url)
    if url.scheme == "http" && client_url.scheme == "http" && url.host&.downcase == "localhost" && client_url.host&.downcase == "localhost"
      url = url.dup.tap { |uri| uri.port = nil }
      client_url = client_url.dup.tap { |uri| uri.port = nil }
    end

    super(url.to_s, client_url.to_s)
  end
end

Doorkeeper::OAuth::Helpers::URIChecker.singleton_class.prepend(DoorkeeperLocalhostPorts)
