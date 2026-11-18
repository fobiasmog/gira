# One OpenSpec file of a change, open or archived, by its path (spec
# openspec-changes, "Files of a change"; add-change-conversation design.md,
# decision 5). Opening a change lists the paths; this returns one text, so
# that agents read only the files they need.
class Api::Projects::Changes::FilesController < Api::BaseController
  include ProjectScoped
  allow_token_access only: :show

  def show
    change = @project.project_changes.find_by_ref!(params[:change_id])
    file = change.files.find_by!(path: params[:path].to_s)
    render json: { path: file.path, text: file.text }
  end
end
