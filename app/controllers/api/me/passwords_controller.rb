# Change password from settings (spec user-auth, "Change password from settings").
class Api::Me::PasswordsController < Api::BaseController
  # Ends every other session of the user and keeps the current one.
  def update
    user = Current.user

    if user.update(password_challenge: params.fetch(:current_password, "").to_s, password: params.fetch(:password, "").to_s)
      user.sessions.where.not(id: Current.session.id).destroy_all
      head :no_content
    else
      errors = user.errors.to_hash(true)
      errors[:current_password] = errors.delete(:password_challenge) if errors.key?(:password_challenge)
      render_error :unprocessable_content, :validation_failed, fields: errors
    end
  end
end
