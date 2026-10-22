# Whether the project's call is offered and who is in it (spec team-call, "Call
# indicator on the board").
class Api::Projects::CallsController < Api::BaseController
  include ProjectScoped

  def show
    call = ProjectCall.new(@project)
    render json: {
      available: call.available?,
      participants: call.participants.map { |member| UserSerializer.new(member).card }
    }
  end
end
