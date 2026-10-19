# Moves a root task on the board or to the backlog (spec project-board,
# "Place and order tasks").
class Api::Projects::Tasks::PlacementsController < Api::BaseController
  include ProjectScoped

  def update
    task = @project.tasks.kept.find(params[:task_id])
    placed = Board.new(@project).place(task, status_id: params[:status_id], position: params.fetch(:position, 0))

    render json: TaskSerializer.new(placed).card
  end
end
