# Everything the board page needs in one response (spec projects, "Project
# board snapshot").
class Api::Projects::BoardsController < Api::BaseController
  include ProjectScoped

  def show
    sprint = @project.active_sprint
    tasks = @project.tasks.kept.roots.on_board.where(sprint_id: sprint&.id).order(:status_id, :position).includes(:project)

    render json: {
      project: ProjectSerializer.new(@project, viewer: Current.user),
      columns: @project.statuses.map { |status| status.slice(:id, :title, :color, :position, :done) },
      tasks: TaskSerializer.cards(tasks),
      members: @project.members.with_attached_avatar.order(:name).map { |member| UserSerializer.new(member).card },
      labels: @project.labels.order(:title).map { |label| label.slice(:id, :title) },
      active_sprint: sprint&.slice(:id, :title, :starts_on, :ends_on)
    }
  end
end
