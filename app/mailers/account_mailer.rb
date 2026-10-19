class AccountMailer < ApplicationMailer
  def confirmation(user)
    @user = user
    @token = user.generate_token_for(:email_confirmation)
    localized_mail user, "account_mailer.confirmation.subject"
  end

  # Sent to an account holder when someone registers with their address.
  def attempted_registration(user)
    @user = user
    localized_mail user, "account_mailer.attempted_registration.subject"
  end

  def unlock(user)
    @user = user
    @token = user.generate_token_for(:unlock)
    localized_mail user, "account_mailer.unlock.subject"
  end
end
