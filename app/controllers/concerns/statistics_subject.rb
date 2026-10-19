# Statistics are about the current user, or about a teammate given as
# ?user_id=. Anyone else is answered as if they did not exist (404).
module StatisticsSubject
  extend ActiveSupport::Concern

  private
    def statistics
      subject = params[:user_id].present? ? find_subject(params[:user_id]) : Current.user
      Statistics.new(subject: subject, viewer: Current.user)
    end

    def find_subject(id)
      id.to_s == Current.user.id.to_s ? Current.user : Current.user.teammates.find(id)
    end
end
