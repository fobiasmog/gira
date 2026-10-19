# Tasks (spec tasks; board and backlog listing from spec project-board).
class Api::Projects::TasksController < Api::BaseController
  include ProjectScoped
  before_action :set_task, only: %i[ show update destroy ]

  VIEWS = %w[board backlog archived].freeze

  # ?view=board (default): root tasks on the board, honouring the active sprint
  # ?view=backlog: root tasks not placed on a column
  # ?view=archived: archived tasks, newest first
  def index
    tasks = case params.fetch(:view, "board").presence_in(VIEWS)
    when "board" then board_tasks(@project)
    when "backlog" then @project.tasks.kept.roots.in_backlog.order(:sprint_id, :position)
    when "archived" then @project.tasks.archived.order(archived_at: :desc, id: :desc)
    else raise ActiveRecord::RecordNotFound
    end

    render json: TaskSerializer.cards(tasks.includes(:project))
  end

  def show
    render json: TaskSerializer.new(@task).detail
  end

  # A task created on a column joins the active sprint unless the client asks
  # for it to stay outside (outside_sprint: true).
  def create
    task = @project.tasks.new(task_params.merge(status_id: params[:status_id], label_id: params[:label_id], creator: Current.user))
    task.sprint = @project.active_sprint if task.status_id && !ActiveModel::Type::Boolean.new.cast(params[:outside_sprint])
    track_assignment(task) { task.save! }

    render json: TaskSerializer.new(task).detail, status: :created
  end

  def update
    @task.assign_attributes(task_params)
    track_assignment(@task) { @task.save! }

    render json: TaskSerializer.new(@task).detail
  end

  # Archives the task.
  def destroy
    raise ActiveRecord::RecordNotFound if @task.archived?

    @task.archive!
    head :no_content
  end

  private
    def set_task
      @task = @project.tasks.find_by_ref!(params[:id])
    end

    def task_params
      params.permit(:title, :description, :deadline, :important, :assignee_id, :milestone_id)
    end

    def board_tasks(project)
      project.tasks.kept.roots.on_board.where(sprint_id: project.active_sprint&.id).order(:status_id, :position)
    end

    # Runs the save and, only when it succeeds, notifies a newly assigned user.
    def track_assignment(task)
      previous = task.persisted? ? task.assignee_id_was : nil
      yield
      TaskAssignment.notify(task, previous_assignee_id: previous, actor: Current.user)
    end
end
