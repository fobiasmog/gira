# Authorization server metadata (RFC 8414; spec mcp-authorization,
# "Authorization server metadata"; add-mcp-oauth design.md, decision 3),
# which MCP clients read after the MCP server's protected resource metadata
# names Goalner as its authorization server.
#
# offline_access is not listed: refresh tokens are always issued, and
# clients would otherwise ask for a scope Doorkeeper does not know. While
# client ID metadata documents are paused, client_id_metadata_document_supported
# is false, so MCP clients fall back to dynamic registration.
class Oauth::MetadataController < ActionController::API
  def show
    response.headers["Cache-Control"] = "public, max-age=3600"
    response.headers["Access-Control-Allow-Origin"] = "*"
    render json: {
      issuer: Oauth.issuer,
      authorization_endpoint: "#{Oauth.issuer}/oauth/authorize",
      token_endpoint: "#{Oauth.issuer}/oauth/token",
      registration_endpoint: "#{Oauth.issuer}/oauth/register",
      revocation_endpoint: "#{Oauth.issuer}/oauth/revoke",
      response_types_supported: %w[code],
      response_modes_supported: %w[query],
      grant_types_supported: %w[authorization_code refresh_token],
      code_challenge_methods_supported: %w[S256],
      token_endpoint_auth_methods_supported: %w[none],
      revocation_endpoint_auth_methods_supported: %w[none],
      scopes_supported: Oauth::SCOPES,
      client_id_metadata_document_supported: Oauth.client_metadata_documents?
    }
  end
end
