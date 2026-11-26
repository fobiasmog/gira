# Moves a root task to a column and position within its change (spec
# project-board, "Place and order tasks").
class Api::Projects::Tasks::PlacementsController < Api::BaseController
  include ProjectScoped
  allow_token_access only: :update

  def update
    task = @project.tasks.kept.find_by_ref!(params[:task_id])
    placed = Board.new(@project).place(task, status_id: params[:status_id], position: params.fetch(:position, 0))

    render json: TaskSerializer.new(placed).card
  end
end
