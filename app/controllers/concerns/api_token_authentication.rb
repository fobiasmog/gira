# Authenticates requests by a personal API token (spec api-tokens; design.md,
# decisions 1, 2, 4 and 12). Included by Api::BaseController and FilesController.
#
# - A request is in token mode when its Authorization header uses the Bearer
#   scheme. Only the token authenticates it: the session cookie is never read,
#   so no CSRF token is needed. Other requests use the session as before.
# - An action refuses tokens unless opened with allow_token_access, and a
#   read-only token is refused every method other than GET and HEAD.
# - Each token may make REQUESTS_PER_MINUTE requests a minute, counted across
#   every including controller (decision 11). Session requests are not limited.
# - An agent token issued for one channel only works on that channel (spec
#   agents, "Agent token channels"; add-agents design.md, decision 7). The
#   MCP server sends its service key with every request, so a request with
#   the key came through MCP, and one with no key is a direct API request.
#   On the other channel the token is unknown: 401 invalid_token. Any other
#   key is the MCP server's own fault, not the token's, and is answered 401
#   invalid_service_key, which the MCP server reports as "unavailable".
#   Every other token ignores the key, which authenticates nothing by itself.
#
# Including controllers answer refusals in render_token_error(status, code).
module ApiTokenAuthentication
  extend ActiveSupport::Concern

  REQUESTS_PER_MINUTE = 300
  SERVICE_KEY_HEADER = "X-Goalner-Service-Key"

  # Included after require_authentication is declared, so the limit runs once
  # the token is known.
  included do
    class_attribute :token_actions, instance_writer: false, default: Set.new.freeze
    skip_forgery_protection if: :bearer_token_request?
    rate_limit to: REQUESTS_PER_MINUTE, within: 1.minute, scope: "api_token_requests",
      by: -> { Current.api_token.id }, if: -> { Current.api_token },
      with: -> { render_token_error :too_many_requests, :rate_limited }
  end

  class_methods do
    # Opens actions to API tokens. Every other action answers a token with 403.
    def allow_token_access(only:)
      self.token_actions = (token_actions + Array(only).map(&:to_s)).freeze
    end
  end

  private
    # By the scheme, not the header's presence: browsers send Basic credentials
    # on their own, but never Bearer. A malformed Bearer header is token mode
    # too, and gets 401.
    def bearer_token_request?
      request.authorization.to_s.start_with?("Bearer")
    end

    def require_authentication
      bearer_token_request? ? authenticate_by_api_token : super
    end

    def resume_session
      super unless bearer_token_request?
    end

    def authenticated?
      bearer_token_request? ? Current.api_token.present? : super
    end

    def authenticate_by_api_token
      api_token = authenticate_with_http_token { |value| ApiToken.find_active_by_value(value) }
      return render_token_error(:unauthorized, :invalid_token) unless api_token
      if (refusal = channel_refusal(api_token))
        return render_token_error(:unauthorized, refusal)
      end

      Current.api_token = api_token
      api_token.touch_last_used!

      if !token_actions.include?(action_name)
        render_token_error :forbidden, :token_not_allowed
      elsif api_token.read? && !(request.get? || request.head?)
        render_token_error :forbidden, :insufficient_scope
      end
    end

    # The error code that refuses api_token on this request's channel, if any.
    def channel_refusal(api_token)
      return unless api_token.single_channel?

      given = request.headers[SERVICE_KEY_HEADER]
      channel = if given.nil?
        "api"
      elsif mcp_service_key?(given)
        "mcp"
      end

      if channel.nil?
        :invalid_service_key
      elsif !api_token.channel?(channel)
        :invalid_token
      end
    end

    def mcp_service_key?(given)
      expected = Rails.configuration.x.oauth.service_key.to_s
      expected.present? && ActiveSupport::SecurityUtils.secure_compare(given.to_s, expected)
    end
end
