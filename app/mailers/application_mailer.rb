class ApplicationMailer < ActionMailer::Base
  default from: -> { Rails.application.credentials.dig(:mailer, :from) || "Goalner <no-reply@goalner.test>" }
  layout "mailer"
  self.delivery_job = MailDeliveryJob

  private
    # Every email is written in the recipient's language.
    def localized_mail(user, subject_key, **headers)
      I18n.with_locale(user.lang) do
        mail(to: user.email_address, subject: t(subject_key), **headers)
      end
    end
end
