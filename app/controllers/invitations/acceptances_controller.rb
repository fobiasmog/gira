class Invitations::AcceptancesController < ApplicationController
  def create
    invitation = Invitation.find_usable(params[:invitation_token])
    return render("invitations/invalid", status: :not_found) unless invitation

    if invitation.addressed_to?(Current.user)
      invitation.accept!(Current.user)
      redirect_to app_path("projects/#{invitation.project_id}")
    else
      @invitation = invitation
      render "invitations/show", status: :forbidden
    end
  end
end
