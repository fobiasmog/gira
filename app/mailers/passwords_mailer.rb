class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    localized_mail user, "passwords_mailer.reset.subject"
  end
end
