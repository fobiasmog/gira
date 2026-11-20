# Archives a change, whatever the state of its tasks, which stay with it (spec
# changes, "Archive a change"), and cancels its open request as the archiver,
# under the project's lock, which frees its agent (add-change-requests
# design.md, decision 10). Archiving an archived change changes nothing.
class Api::Projects::Changes::ArchivalsController < Api::BaseController
  include ProjectScoped
  allow_token_access only: :create

  def create
    change = @project.project_changes.find_by_ref!(params[:change_id])
    change.archive!(by: Current.user)
    render json: ChangeSerializer.new(change)
  end
end
