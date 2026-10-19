# Puts a root task into one of the project's sprints, or takes it out
# (sprint_id: null). A task belongs to at most one sprint.
class Api::Projects::Tasks::SprintsController < Api::BaseController
  include ProjectScoped

  def update
    task = @project.tasks.kept.find(params[:task_id])
    task.update!(sprint_id: params[:sprint_id])
    render json: TaskSerializer.new(task).card
  end
end
