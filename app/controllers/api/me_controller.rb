# The signed-in user's own profile (spec user-profile).
class Api::MeController < Api::BaseController
  allow_token_access only: :show
  def show
    render json: UserSerializer.new(Current.user).profile
  end

  def update
    user = Current.user
    user.assign_attributes(params.permit(:name, :lang))
    user.merge_contact_links(params.fetch(:contact_links, {}).permit(*User::CONTACT_SERVICES)) if params.key?(:contact_links)

    if user.save
      render json: UserSerializer.new(user).profile
    else
      render_validation_errors user
    end
  end
end
