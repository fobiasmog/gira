class Api::Me::AvatarsController < Api::BaseController
  def update
    user = Current.user

    if user.replace_avatar(params.require(:avatar))
      render json: UserSerializer.new(user).profile
    else
      render_validation_errors user
    end
  end
end
