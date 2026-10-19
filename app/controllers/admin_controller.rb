# Base controller for operational interfaces (Mission Control Jobs). Reached
# only through AdminConstraint; checks the admin flag again here as a second
# line of defence. Mission Control's inline importmap needs a CSP nonce,
# which is enabled on these pages only.
class AdminController < ApplicationController
  before_action :require_admin
  before_action :enable_script_nonce

  private
    def require_admin
      raise ActionController::RoutingError, "Not Found" unless Current.user&.admin?
    end

    def enable_script_nonce
      request.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
      request.content_security_policy_nonce_directives = %w[script-src]
    end
end
