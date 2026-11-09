# The exchange of an MCP connection's access token for a connection token
# (spec api-tokens, "Connection tokens"; add-mcp-oauth design.md, decision 8).
# Only the MCP server calls it, over the private network: nginx refuses
# /internal/ from outside, and the service key is the second lock. The key
# alone opens nothing: it needs a live access token of a user's connection.
#
# 1. The service key (X-Goalner-Service-Key) must equal MCP_SERVICE_KEY.
# 2. The access token must be live, issued by Goalner for the MCP resource.
#    Its row, found by digest, proves Goalner issued it, so its signature is
#    not checked again, and rotating the signing key forces no refresh
#    (harden-mcp-oauth design.md, decision 4).
# 3. Its first use completes refresh rotation: the refresh token it replaced
#    stops working (spec mcp-authorization, "Old refresh token"). The MCP
#    server exchanges a new access token on the first request it sees with
#    it, whatever the request, tool lists included (harden-mcp-oauth
#    design.md, decision 1).
# 4. 60 exchanges an hour per access token.
# 5. A connection token is issued, valid no longer than the access token.
#
# No session and no CSRF token: an ActionController::API.
class Internal::McpTokenExchangesController < ActionController::API
  EXCHANGES_PER_HOUR = 60

  before_action :require_service_key
  before_action :find_access_token
  rate_limit to: EXCHANGES_PER_HOUR, within: 1.hour, by: -> { @access_token.id }, scope: "mcp_token_exchanges",
    with: -> { render json: { error: "rate_limited" }, status: :too_many_requests }

  def create
    api_token = ApiToken.issue_for_connection!(@access_token)
    render json: { token: api_token.value, expires_at: api_token.expires_at, access: api_token.access }, status: :created
  end

  private
    def require_service_key
      expected = Rails.configuration.x.oauth.service_key.to_s
      given = request.headers["X-Goalner-Service-Key"].to_s
      return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(given, expected)

      render json: { error: "invalid_service_key" }, status: :unauthorized
    end

    def find_access_token
      value = params[:access_token]
      @access_token = Oauth::AccessToken.by_token(value) if value.is_a?(String) && value.present?
      unless @access_token&.accessible? && Oauth::JwtGenerator.claims(value)
        return render json: { error: "invalid_token" }, status: :unauthorized
      end

      @access_token.revoke_previous_refresh_token!
    end
end
