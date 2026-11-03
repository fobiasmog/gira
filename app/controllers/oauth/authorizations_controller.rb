# Authorization requests and consent (spec mcp-authorization, "Authorization
# requests", "Sign-in before consent", "Consent page" and "Consent decision";
# add-mcp-oauth design.md, decisions 1 and 6). Doorkeeper validates the
# request and issues the code. Through ApplicationController, a visitor is
# sent to sign-in and brought back to the same request.
#
# - Only the query response mode, and only Goalner's MCP resource.
# - Consent is always shown; no password is asked.
# - Errors redirect to the client when its redirect URI is registered for it,
#   with an English error_description, and render an error page otherwise.
class Oauth::AuthorizationsController < Doorkeeper::AuthorizationsController
  layout "application"

  # RFC 7636 4.4.1 answers an unsupported code challenge method, such as
  # plain, with invalid_request; Doorkeeper names an error of its own.
  module PlainChallengeIsInvalidRequest
    def error_response
      return super unless error == Doorkeeper::Errors::InvalidCodeChallengeMethod

      Doorkeeper::OAuth::InvalidRequestResponse.new(state: state, redirect_uri: redirect_uri,
        reason: :invalid_code_challenge_method, response_on_fragment: false)
    end
  end

  before_action :resolve_client_metadata_document, except: :show
  before_action :narrow_scope, only: :create
  before_action :refuse_unsupported_parameters, except: :show

  def new
    allow_form_action_to_redirect_origin if pre_auth.authorizable?
    super
  end

  # Out-of-band redirect URIs are never registered, so the page that would
  # show their codes is not served.
  def show
    head :not_found
  end

  private
    # A client id that is an HTTPS URL names its metadata document, which is
    # stored as the client before Doorkeeper looks it up (design.md, decision
    # 4). A refused document gets the error page, never a redirect.
    def resolve_client_metadata_document
      return unless Oauth::ClientMetadataDocument.client_id?(params[:client_id])

      Oauth::ClientMetadataDocument.resolve(params[:client_id], redirect_uri: params[:redirect_uri].presence&.to_s)
    rescue Oauth::ClientMetadataDocument::Error => error
      logger.info "Client ID metadata document refused: #{error.message}"
      render :error, locals: { error_response: Doorkeeper::OAuth::ErrorResponse.new(name: :invalid_client) }, status: :bad_request
    end

    # The code is bound to the access chosen at consent: read, or read and
    # write when the user chose read-write and the client asked for write
    # (design.md, decision 6). Refresh keeps it. A scope outside read and
    # write is left for Doorkeeper to refuse.
    def narrow_scope
      requested = Doorkeeper::OAuth::Scopes.from_string(params[:scope].to_s)
      return unless requested.all.all? { |scope| Oauth::SCOPES.include?(scope) }

      params[:scope] = params[:access] == "read_write" && requested.exists?("write") ? "read write" : "read"
    end

    # Doorkeeper's form_post response needs inline script, which the CSP
    # forbids, so only query is served. A resource other than the MCP
    # endpoint is refused with invalid_target (RFC 8707). Both redirect to the
    # client once its redirect URI checks out (design.md, decision 6).
    def refuse_unsupported_parameters
      error = if params[:response_mode].present? && params[:response_mode] != "query"
        :unsupported_response_mode
      elsif params[:resource].present? && params[:resource] != Oauth.resource
        :invalid_target
      end
      return if error.nil? || refuse_invalid_client?

      error_response = Doorkeeper::OAuth::ErrorResponse.new(name: error, state: params[:state], redirect_uri: pre_auth.redirect_uri,
        response_on_fragment: false)
      I18n.with_locale(:en) { redirect_to error_response.redirect_uri, allow_other_host: true }
    end

    def pre_auth
      @pre_auth ||= super.extend(PlainChallengeIsInvalidRequest)
    end

    # The consent form posts to this application, which then redirects to
    # the client. Chrome and Firefox apply form-action to that redirect too,
    # so this response alone also allows the origin of the validated redirect
    # URI (spec security-baseline, "Consent page form action").
    def allow_form_action_to_redirect_origin
      uri = URI(pre_auth.redirect_uri)
      origin = "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.port == uri.default_port}"
      policy = current_content_security_policy
      policy.form_action :self, origin
      request.content_security_policy = policy
    end

    # Error descriptions are for client developers, and are not translated.
    def redirect_or_render(auth)
      I18n.with_locale(:en) { super }
    end
end
