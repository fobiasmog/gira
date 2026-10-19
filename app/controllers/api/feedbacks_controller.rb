class Api::FeedbacksController < Api::BaseController
  rate_limit_per_user to: 5, within: 1.hour, only: :create

  def create
    feedback = Feedback.new(params.permit(:reason, :message))

    if feedback.deliver_from(Current.user)
      head :accepted
    else
      render_validation_errors feedback
    end
  end
end
