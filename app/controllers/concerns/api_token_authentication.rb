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
#
# Including controllers answer refusals in render_token_error(status, code).
module ApiTokenAuthentication
  extend ActiveSupport::Concern

  # Any header in the Bearer scheme selects token mode, even a malformed one.
  BEARER_SCHEME = /\ABearer(?:\s|\z)/i
  BEARER_VALUE = /\ABearer\s+(\S+)\s*\z/i
  REQUESTS_PER_MINUTE = 300

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
    # on their own, but never Bearer.
    def bearer_token_request?
      request.authorization.to_s.match?(BEARER_SCHEME)
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
      api_token = ApiToken.find_active_by_value(request.authorization.to_s[BEARER_VALUE, 1])
      return render_token_error(:unauthorized, :invalid_token) unless api_token

      Current.api_token = api_token
      api_token.touch_last_used!

      if !token_actions.include?(action_name)
        render_token_error :forbidden, :token_not_allowed
      elsif api_token.read? && !(request.get? || request.head?)
        render_token_error :forbidden, :insufficient_scope
      end
    end
end
