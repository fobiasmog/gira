# The page an invitation link opens (spec project-membership, "Accept an
# invitation"). Visitors are asked to sign in or sign up and are brought back
# here afterwards; signed-in users see an accept button if the invitation was
# sent to their confirmed address.
class InvitationsController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    @invitation = Invitation.find_usable(params[:token])
    return render(:invalid, status: :not_found) unless @invitation

    session[:return_to_after_authenticating] = request.url unless authenticated?
  end
end
