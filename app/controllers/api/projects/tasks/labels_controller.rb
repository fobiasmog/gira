# A task's single label (spec labels, "Label a task").
class Api::Projects::Tasks::LabelsController < Api::BaseController
  include ProjectScoped
  allow_token_access only: %i[ update destroy ]
  before_action :set_task

  def update
    @task.update!(label_id: params.require(:label_id))
    render json: TaskSerializer.new(@task).card
  end

  def destroy
    @task.update!(label_id: nil)
    render json: TaskSerializer.new(@task).card
  end

  private
    def set_task
      @task = @project.tasks.kept.find(params[:task_id])
    end
end
