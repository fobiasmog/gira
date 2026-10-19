class InvitationMailerPreview < ActionMailer::Preview
  def invite
    inviter = User.new(name: "Ada Lovelace", email_address: "ada@example.com", lang: params[:locale] || "en")
    project = Project.new(id: 1, title: "Analytical Engine", short_name: "AE")
    InvitationMailer.invite(Invitation.new(email: "charles@example.com", project: project, inviter: inviter), "preview-token")
  end
end
