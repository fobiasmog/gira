class InvitationSerializer
  def initialize(invitation)
    @invitation = invitation
  end

  def as_json(*)
    { id: @invitation.id, email: @invitation.email, expires_at: @invitation.expires_at, inviter_id: @invitation.inviter_id }
  end
end
