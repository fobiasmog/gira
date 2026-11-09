# The token and revocation endpoints (spec mcp-authorization, "Access
# tokens", "Refresh tokens" and "Token revocation endpoint"; add-mcp-oauth
# design.md, decisions 1 and 6). An ActionController::API through Doorkeeper:
# public clients call it form-encoded, with no session and no CSRF token
# (spec security-baseline, "Token endpoint without a session").
#
# - A token request naming a resource other than the MCP endpoint is refused
#   with invalid_target (RFC 8707), as at the authorization endpoint.
# - A code or refresh token is redeemed while its user's row is locked, as
#   every path that ends connections locks it (McpConnection.revoke). A
#   connection that ends meanwhile therefore either makes Doorkeeper refuse
#   the request, or has the new token revoked with it (harden-mcp-oauth
#   design.md, decision 2).
# - Using a refresh token ends the one it replaced: the client received it,
#   so rotation is complete (decision 1). The new access token's first use
#   at the MCP server ends it too (Internal::McpTokenExchangesController).
class Oauth::TokensController < Doorkeeper::TokensController
  before_action :refuse_other_resource, only: :create

  def create
    presented = presented_code_or_refresh_token
    return super unless presented

    ApplicationRecord.transaction do
      User.lock.find(presented.resource_owner_id)
      presented.class.find_by(id: presented.id)&.revoke_previous_refresh_token! if presented.is_a?(Oauth::AccessToken)
      super
    end
  end

  private
    def refuse_other_resource
      return if params[:resource].blank? || params[:resource] == Oauth.resource

      response.headers["Cache-Control"] = "no-store"
      render json: { error: "invalid_target", error_description: I18n.t("doorkeeper.errors.messages.invalid_target", locale: :en) },
        status: :bad_request
    end

    # The grant or token row the request presents, found by digest; nil for
    # an unknown one, which Doorkeeper then refuses without a lock. Read
    # uncached: Doorkeeper repeats the same query once the lock is held, and
    # must not be answered with this row from before it.
    def presented_code_or_refresh_token
      ApplicationRecord.uncached do
        case params[:grant_type]
        when "authorization_code"
          Oauth::AccessGrant.by_token(params[:code]) if params[:code].is_a?(String) && params[:code].present?
        when "refresh_token"
          Oauth::AccessToken.by_refresh_token(params[:refresh_token]) if params[:refresh_token].is_a?(String) && params[:refresh_token].present?
        end
      end
    end
end
