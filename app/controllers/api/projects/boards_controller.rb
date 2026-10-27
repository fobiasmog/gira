# Everything the board page needs in one response (spec projects, "Project
# board snapshot").
class Api::Projects::BoardsController < Api::BaseController
  include ProjectScoped
  allow_token_access only: :show

  def show
    sprint = @project.active_sprint
    # The active sprint's tasks, or the tasks in no sprint when none is active.
    tasks = @project.tasks.kept.roots.where(sprint_id: sprint&.id).in_column_order.includes(:project)

    render json: {
      project: ProjectSerializer.new(@project, viewer: Current.user),
      columns: @project.statuses.map { |status| StatusSerializer.new(status) },
      tasks: TaskSerializer.cards(tasks),
      members: @project.members.with_attached_avatar.order(:name).map { |member| UserSerializer.new(member).card },
      labels: @project.labels.order(:title).map { |label| label.slice(:id, :title) },
      active_sprint: sprint&.slice(:id, :title, :starts_on, :ends_on)
    }
  end
end
