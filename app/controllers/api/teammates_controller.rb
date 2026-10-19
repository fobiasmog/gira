class Api::TeammatesController < Api::BaseController
  def index
    teammates = Current.user.teammates.with_attached_avatar.order(:name)
    render json: teammates.map { |teammate| UserSerializer.new(teammate).card }
  end
end
