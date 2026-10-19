# Invitations (spec project-membership). Creating one answers the same way
# whether the address is unknown, registered, already invited or a member.
class Api::Projects::InvitationsController < Api::BaseController
  include ProjectScoped
  rate_limit_per_user to: 20, within: 1.hour, only: :create, scope: "invitations"

  def index
    invitations = @project.invitations.usable.order(:created_at)
    render json: invitations.map { |invitation| InvitationSerializer.new(invitation) }
  end

  def create
    Invitation.invite(project: @project, inviter: Current.user, email: params.require(:email))
    render json: { message: t("invitations.sent") }, status: :accepted
  end

  def destroy
    invitation = @project.invitations.pending.find(params[:id])
    raise Forbidden unless invitation.revocable_by?(Current.user)

    invitation.revoke!
    head :no_content
  end
end
