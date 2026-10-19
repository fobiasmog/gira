class FeedbackMailer < ApplicationMailer
  def feedback(user, reason:, message:)
    @user = user
    @reason = reason
    @message = message

    I18n.with_locale(:en) do
      mail to: Rails.application.credentials.dig(:feedback, :operators_email) || "operators@goalner.test",
        reply_to: user.email_address, subject: "Goalner feedback: #{reason.truncate(60)}"
    end
  end
end
