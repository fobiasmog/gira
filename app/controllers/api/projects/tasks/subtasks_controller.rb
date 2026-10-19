# Subtasks (spec tasks, "Subtasks"). A subtask starts in the project's first
# column and cannot have subtasks of its own.
class Api::Projects::Tasks::SubtasksController < Api::BaseController
  include ProjectScoped
  before_action :set_parent

  def index
    render json: TaskSerializer.cards(@parent.subtasks.includes(:project))
  end

  def create
    subtask = @project.tasks.new(title: params.require(:title), parent: @parent, creator: Current.user,
      status: @project.first_status)
    subtask.save!

    render json: TaskSerializer.new(subtask).card, status: :created
  end

  private
    def set_parent
      @parent = @project.tasks.kept.find(params[:task_id])
    end
end
