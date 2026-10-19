class Api::AnnouncementsController < Api::BaseController
  def index
    render json: Announcement.visible_to(Current.user).map { |announcement| announcement.slice(:id, :body, :created_at) }
  end

  # Dismisses every announcement the user currently sees.
  def destroy
    Announcement.dismiss_all_for(Current.user)
    head :no_content
  end
end
