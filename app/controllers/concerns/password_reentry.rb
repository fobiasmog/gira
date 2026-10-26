# Settings actions that ask for the current password again (design.md,
# decision 7). The check shares the sign-in lockout, and a refusal is the same
# 422 on current_password whether the password is wrong or the account is
# locked. Declare it with before_action, after any rate limit.
module PasswordReentry
  extend ActiveSupport::Concern

  private
    def require_reentered_password
      return if Current.user.verify_reentered_password(params[:current_password])

      message = ActiveModel::Error.new(Current.user, :password_challenge, :invalid).full_message
      render_error :unprocessable_content, :validation_failed, fields: { current_password: [ message ] }
    end
end
