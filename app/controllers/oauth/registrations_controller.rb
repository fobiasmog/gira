# Dynamic client registration (RFC 7591; spec mcp-authorization, "Dynamic
# client registration"; add-mcp-oauth design.md, decision 5), for MCP clients
# that do not publish a client ID metadata document. No session and no CSRF
# token: anyone may register, so registration grants nothing by itself.
#
# - The client is always public (token_endpoint_auth_method "none"),
#   whatever method it asked for, as RFC 7591 allows, so no secret is issued.
# - Redirect URIs are HTTPS, or HTTP on a loopback address.
# - 20 registrations an hour per IP address; clients never authorized are
#   deleted after 24 hours (PurgeMcpConnectionsJob). There is no registration
#   access token and no client management endpoint.
class Oauth::RegistrationsController < ActionController::API
  REGISTRATIONS_PER_HOUR = 20
  MAX_REDIRECT_URIS = 10

  rate_limit to: REGISTRATIONS_PER_HOUR, within: 1.hour, by: -> { request.remote_ip }, scope: "oauth_registrations",
    with: -> { render_error :too_many_requests, "too_many_requests", "Too many registrations. Try again later." }

  def create
    redirect_uris = params[:redirect_uris]
    unless redirect_uris.is_a?(Array) && redirect_uris.length.between?(1, MAX_REDIRECT_URIS) &&
        redirect_uris.all? { |uri| Oauth.allowed_redirect_uri?(uri) }
      return render_error :bad_request, "invalid_redirect_uri", "Redirect URIs must use HTTPS, or HTTP on a loopback address."
    end

    name = client_name(redirect_uris)
    return render_error :bad_request, "invalid_client_metadata", "client_name must be at most 100 characters." unless name

    application = Oauth::Application.create!(name: name, redirect_uri: redirect_uris.join(" "), registration: :dcr, confidential: false)
    render json: {
      client_id: application.uid,
      client_id_issued_at: application.created_at.to_i,
      client_name: application.name,
      redirect_uris: application.redirect_uris,
      grant_types: %w[authorization_code refresh_token],
      response_types: %w[code],
      token_endpoint_auth_method: "none"
    }, status: :created
  end

  private
    # The given name, or the first 100 characters of the first redirect
    # URI's host (harden-mcp-oauth design.md, decision 5); nil when the given
    # name is too long.
    def client_name(redirect_uris)
      name = params[:client_name]
      return URI(redirect_uris.first).host.first(Oauth::MAX_NAME_LENGTH) if name.blank?

      name.strip if name.is_a?(String) && name.strip.length <= Oauth::MAX_NAME_LENGTH
    end

    def render_error(status, code, description)
      render json: { error: code, error_description: description }, status: status
    end
end
