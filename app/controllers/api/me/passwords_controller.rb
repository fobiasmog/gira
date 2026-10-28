# Change password from settings (spec user-auth, "Change password from settings").
class Api::Me::PasswordsController < Api::BaseController
  include PasswordReentry
  before_action :require_reentered_password

  # Ends every other session of the user and keeps the current one.
  def update
    user = Current.user

    if user.update(password: params.fetch(:password, "").to_s)
      user.sessions.where.not(id: Current.session.id).destroy_all
      head :no_content
    else
      render_validation_errors user
    end
  end
end
