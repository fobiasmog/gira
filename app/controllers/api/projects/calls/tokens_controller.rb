# An access token for the project's call, for members only (spec team-call,
# "Call access tokens"). The browser connects to the media server with it.
class Api::Projects::Calls::TokensController < Api::BaseController
  include ProjectScoped
  rate_limit_per_user to: 20, within: 1.minute, only: :create

  def create
    call = ProjectCall.new(@project)
    raise ActiveRecord::RecordNotFound unless call.available?

    render json: { url: call.url, token: call.token_for(Current.user) }, status: :created
  end
end
