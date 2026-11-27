# The JSON error envelope of the API (spec security-baseline): one shape,
# { error: { code:, message:, fields: } }, that never contains exception
# messages, SQL or class names. Included by Api::BaseController and by the
# runner endpoints (Api::Runners::BaseController), which have no session.
module ApiErrors
  extend ActiveSupport::Concern

  MESSAGES = {
    unauthorized: "Sign in to continue.",
    invalid_token: "The API token is missing, invalid or expired.",
    invalid_runner_secret: "The runner secret is missing, invalid or revoked. Register the runner again with its current secret.",
    agent_leased: "This agent runs on another runner.",
    workspace_elsewhere: "This agent's change has its workspace on another runner.",
    invalid_service_key: "The service key sent with this request was refused.",
    forbidden: "You do not have permission to do this.",
    agents_only: "Only agents can do this. Connect with an agent's token.",
    token_not_allowed: "This action is not available with an API token.",
    insufficient_scope: "This API token is read-only.",
    not_found: "Not found.",
    invalid_authenticity_token: "Your session has expired. Reload the page and try again.",
    validation_failed: "Some fields are invalid.",
    keys_missing: "This change already has tasks, but the text carries none of their Goalner marks. Save the text returned here into tasks.md, edit it, and import again.",
    rate_limited: "Too many requests. Try again later.",
    internal_error: "Something went wrong. Please try again."
  }.freeze

  # Order matters: rescue_from handlers are searched bottom-up, so handlers
  # declared by including controllers come first.
  included do
    rescue_from StandardError, with: :render_internal_error
    rescue_from ActiveRecord::RecordNotFound, ActionController::RoutingError, with: :render_not_found
    rescue_from ActiveRecord::RecordInvalid, Board::Error, with: :render_record_invalid
    rescue_from ActionController::ParameterMissing, with: :render_parameter_missing
    rescue_from ActionController::TooManyRequests, with: :render_rate_limited
  end

  private
    # details: more about the error, such as who holds what was refused.
    def render_error(status, code, fields: nil, details: nil)
      error = { code: code.to_s, message: MESSAGES.fetch(code) }
      error[:fields] = fields if fields
      error.merge!(details) if details
      render json: { error: error }, status: status
    end

    def render_validation_errors(record)
      render_error :unprocessable_content, :validation_failed, fields: record.errors.to_hash(true)
    end

    def render_not_found(_exception = nil)
      render_error :not_found, :not_found
    end

    def render_record_invalid(exception)
      render_validation_errors exception.record
    end

    def render_parameter_missing(exception)
      render_error :unprocessable_content, :validation_failed, fields: { exception.param => [ "is required" ] }
    end

    def render_rate_limited(_exception = nil)
      render_error :too_many_requests, :rate_limited
    end

    def render_internal_error(exception)
      Rails.error.report(exception, handled: true, source: "api")
      render_error :internal_server_error, :internal_error
    end
end
