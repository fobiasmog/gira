# Puts a root task into one of the project's open changes, moves it to
# another, or takes it out (change_id: null), keeping its column; its
# subtasks follow (spec changes, "Tasks in a change"). A card of its change's
# tasks.md stays where it is.
class Api::Projects::Tasks::ChangesController < Api::BaseController
  include ProjectScoped
  allow_token_access only: :update

  def update
    task = @project.tasks.kept.find_by_ref!(params[:task_id])
    task.update!(change_id: params[:change_id])
    render json: TaskSerializer.new(task).card
  end
end
