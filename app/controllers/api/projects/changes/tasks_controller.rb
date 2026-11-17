# One change's root, non-archived tasks, done ones included, in column order
# (spec changes, "Change task list"). Archived changes too.
class Api::Projects::Changes::TasksController < Api::BaseController
  include ProjectScoped
  allow_token_access only: :index

  def index
    change = @project.project_changes.find_by_ref!(params[:change_id])
    render json: TaskSerializer.cards(change.tasks.kept.roots.in_column_order)
  end
end
