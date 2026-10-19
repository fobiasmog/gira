# Base for every JSON endpoint under /api (spec security-baseline).
#
# - Authentication: the session cookie, as for pages, but an anonymous request
#   gets 401 JSON instead of a redirect to the sign-in page.
# - CSRF: verified on every non-GET request by ActionController::Base's default
#   forgery protection, before authentication (the SPA sends X-CSRF-Token).
# - Errors: one envelope, { error: { code:, message:, fields: } }, that never
#   contains exception messages, SQL or class names.
class Api::BaseController < ApplicationController
  # Raised when a signed-in member lacks a permission, such as a non-owner
  # renaming a project.
  class Forbidden < StandardError; end

  MESSAGES = {
    unauthorized: "Sign in to continue.",
    forbidden: "You do not have permission to do this.",
    not_found: "Not found.",
    invalid_authenticity_token: "Your session has expired. Reload the page and try again.",
    validation_failed: "Some fields are invalid.",
    rate_limited: "Too many requests. Try again later.",
    internal_error: "Something went wrong. Please try again."
  }.freeze

  # Order matters: rescue_from handlers are searched bottom-up.
  rescue_from StandardError, with: :render_internal_error
  rescue_from ActiveRecord::RecordNotFound, ActionController::RoutingError, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, Board::Error, with: :render_record_invalid
  rescue_from ActionController::ParameterMissing, with: :render_parameter_missing
  rescue_from Forbidden, with: :render_forbidden
  rescue_from ActionController::InvalidAuthenticityToken, with: :render_invalid_authenticity_token
  rescue_from ActionController::TooManyRequests, with: :render_rate_limited

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

    def render_error(status, code, fields: nil)
      error = { code: code.to_s, message: MESSAGES.fetch(code) }
      error[:fields] = fields if fields
      render json: { error: error }, status: status
    end

    def render_validation_errors(record)
      render_error :unprocessable_content, :validation_failed, fields: record.errors.to_hash(true)
    end

    def render_not_found(_exception = nil)
      render_error :not_found, :not_found
    end

    def render_forbidden(_exception = nil)
      render_error :forbidden, :forbidden
    end

    def render_record_invalid(exception)
      render_validation_errors exception.record
    end

    def render_parameter_missing(exception)
      render_error :unprocessable_content, :validation_failed, fields: { exception.param => [ "is required" ] }
    end

    def render_invalid_authenticity_token(_exception = nil)
      render_error :unprocessable_content, :invalid_authenticity_token
    end

    def render_rate_limited(_exception = nil)
      render_error :too_many_requests, :rate_limited
    end

    def render_internal_error(exception)
      Rails.error.report(exception, handled: true, source: "api")
      render_error :internal_server_error, :internal_error
    end
end
