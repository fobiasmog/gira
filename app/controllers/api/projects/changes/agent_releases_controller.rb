# Releases a change's agent (spec change-requests, "Release an agent";
# add-change-requests design.md, decision 6): its taken request is
# cancelled, its block ends, and the change has no agent, so that its waiting
# request is in the shared pool. A change with no agent is left as it is.
class Api::Projects::Changes::AgentReleasesController < Api::BaseController
  include ProjectScoped
  allow_token_access only: :create

  def create
    change = @project.project_changes.find_by_ref!(params[:change_id])
    change.release_agent!(by: Current.user)
    render json: ChangeSerializer.new(change).detail
  end
end
