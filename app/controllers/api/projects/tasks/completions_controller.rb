# Marks a subtask complete (moves it to the done column) or not complete
# (back to the first column).
class Api::Projects::Tasks::CompletionsController < Api::BaseController
  include ProjectScoped
  before_action :set_subtask

  def update
    move_to @project.done_status
  end

  def destroy
    move_to @project.first_status
  end

  private
    def set_subtask
      @subtask = @project.tasks.kept.where.not(parent_id: nil).find(params[:task_id])
    end

    def move_to(status)
      @subtask.update!(status: status)
      render json: TaskSerializer.new(@subtask).card
    end
end
