# The token and revocation endpoints (spec mcp-authorization, "Access
# tokens", "Refresh tokens" and "Token revocation endpoint"; add-mcp-oauth
# design.md, decisions 1 and 6). An ActionController::API through Doorkeeper:
# public clients call it form-encoded, with no session and no CSRF token
# (spec security-baseline, "Token endpoint without a session").
#
# A token request naming a resource other than the MCP endpoint is refused
# with invalid_target (RFC 8707), as at the authorization endpoint.
class Oauth::TokensController < Doorkeeper::TokensController
  before_action :refuse_other_resource, only: :create

  private
    def refuse_other_resource
      return if params[:resource].blank? || params[:resource] == Oauth.resource

      response.headers["Cache-Control"] = "no-store"
      render json: { error: "invalid_target", error_description: I18n.t("doorkeeper.errors.messages.invalid_target", locale: :en) },
        status: :bad_request
    end
end
