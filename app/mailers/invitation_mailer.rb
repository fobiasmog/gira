class InvitationMailer < ApplicationMailer
  # Written in the invitee's language when they have an account, otherwise in
  # the inviter's. Contains no password: the invitee signs up or signs in.
  def invite(invitation, token)
    @invitation = invitation
    @url = invitation_url(token)
    lang = User.find_by(email_address: invitation.email)&.lang || invitation.inviter.lang

    I18n.with_locale(lang) do
      mail to: invitation.email, subject: t("invitation_mailer.invite.subject", project: invitation.project.title)
    end
  end
end
