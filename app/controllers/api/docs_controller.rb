# Interactive documentation of the token API (spec api-documentation,
# "Interactive API documentation"). A page, so anonymous visitors are sent to
# sign-in; a request with an API token is refused with 403, as everywhere
# under /api that is not opened to tokens.
class Api::DocsController < ApplicationController
  include ApiTokenAuthentication
  layout "api_docs"

  def show
  end

  private
    # The JSON envelope of the rest of /api, so token clients get the answer
    # they get everywhere else.
    def render_token_error(status, code)
      render json: { error: { code: code.to_s, message: Api::BaseController::MESSAGES.fetch(code) } }, status: status
    end
end
