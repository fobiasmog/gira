# Moves a root task to a column and position (spec project-board, "Place and
# order tasks"). An optional sprint_id moves it into that sprint, or out of
# its sprint when null, in the same operation (a backlog task put on the board).
class Api::Projects::Tasks::PlacementsController < Api::BaseController
  include ProjectScoped

  def update
    task = @project.tasks.kept.find(params[:task_id])
    sprint = params.key?(:sprint_id) ? { sprint_id: params[:sprint_id] } : {}
    placed = Board.new(@project).place(task, status_id: params[:status_id], position: params.fetch(:position, 0), **sprint)

    render json: TaskSerializer.new(placed).card
  end
end
