# Base for every JSON endpoint under /api (spec security-baseline).
#
# - Authentication: the session cookie, as for pages, but an anonymous request
#   gets 401 JSON instead of a redirect to the sign-in page. A request with an
#   Authorization: Bearer header is authenticated by its API token alone
#   (ApiTokenAuthentication), and only in actions opened with allow_token_access.
# - CSRF: verified on every non-GET session request by ActionController::Base's
#   default forgery protection, before authentication (the SPA sends
#   X-CSRF-Token). Token requests skip it, as they never read the cookie.
# - Errors: one envelope, { error: { code:, message:, fields: } }, that never
#   contains exception messages, SQL or class names (ApiErrors).
class Api::BaseController < ApplicationController
  include ApiErrors
  include ApiTokenAuthentication
  allow_token_access only: :route_not_found

  # Raised when a signed-in member lacks a permission, such as a non-owner
  # renaming a project.
  class Forbidden < StandardError; end

  # After ApiErrors' handlers: rescue_from handlers are searched bottom-up.
  rescue_from Forbidden, with: :render_forbidden
  rescue_from ActionController::InvalidAuthenticityToken, with: :render_invalid_authenticity_token

  # A Current.user-based key for endpoints limited per user.
  def self.rate_limit_per_user(**options)
    rate_limit by: -> { Current.user.id }, with: -> { render_rate_limited }, **options
  end

  # Target of the catch-all /api route, so unknown API paths answer with the
  # JSON envelope too.
  def route_not_found
    render_not_found
  end

  private
    def request_authentication
      render_error :unauthorized, :unauthorized
    end

    def render_token_error(status, code)
      render_error status, code
    end

    def render_forbidden(_exception = nil)
      render_error :forbidden, :forbidden
    end

    def render_invalid_authenticity_token(_exception = nil)
      render_error :unprocessable_content, :invalid_authenticity_token
    end
end
