# Everything the board page needs in one response (spec projects, "Board
# snapshot"): the board of one open change, named by change_id (its id or
# name), or of the tasks in no change without it. An archived change, or one
# of another project, has no board: 404.
class Api::Projects::BoardsController < Api::BaseController
  include ProjectScoped
  allow_token_access only: :show

  def show
    change = @project.project_changes.kept.find_by_ref!(params[:change_id]) if params[:change_id].present?
    tasks = @project.tasks.kept.roots.where(change_id: change&.id).in_column_order

    render json: {
      project: ProjectSerializer.new(@project, viewer: Current.user),
      columns: @project.statuses.map { |status| StatusSerializer.new(status) },
      tasks: TaskSerializer.cards(tasks),
      members: @project.listed_members.map { |member| UserSerializer.new(member).card },
      labels: @project.labels.order(:title).map { |label| label.slice(:id, :title) },
      change: change&.slice(:id, :name),
      changes: ChangeSerializer.list(@project.project_changes.kept.newest_first)
    }
  end
end
