# Tasks (spec tasks; board listing from spec project-board).
class Api::Projects::TasksController < Api::BaseController
  include ProjectScoped
  allow_token_access only: %i[ index show create update destroy ]
  before_action :set_task, only: %i[ show update destroy ]

  VIEWS = %w[board archived assigned].freeze

  # ?view=board (default): root tasks on a board, done ones included, in
  #   column order: the open change named by change_id (its id or name), or
  #   the tasks in no change without it
  # ?view=archived: archived tasks, newest first
  # ?view=assigned: the requester's open tasks, subtasks included, whatever
  #   their change, by column and then by number (spec tasks, "Open tasks
  #   assigned to the requester"). With a token the requester is its owner,
  #   so an agent finds its work here.
  def index
    tasks = case params.fetch(:view, "board").presence_in(VIEWS)
    when "board" then @project.tasks.kept.roots.where(change_id: board_change&.id).in_column_order
    when "archived" then @project.tasks.archived.order(archived_at: :desc, id: :desc)
    when "assigned" then @project.tasks.kept.not_done.where(assignee: Current.user).order("statuses.position", :number)
    else raise ActiveRecord::RecordNotFound
    end

    render json: TaskSerializer.cards(tasks)
  end

  def show
    render json: TaskSerializer.new(@task).detail
  end

  # In the change named by change_id, an open change of the project, or in
  # no change without it; on the first column when no column is named.
  def create
    task = @project.tasks.new(task_params.merge(status_id: params[:status_id], label_id: params[:label_id], change_id: params[:change_id],
      creator: Current.user))
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
      params.permit(:title, :description, :deadline, :important, :assignee_id)
    end

    def board_change
      @project.project_changes.kept.find_by_ref!(params[:change_id]) if params[:change_id].present?
    end

    # Runs the save and, only when it succeeds, notifies a newly assigned user.
    def track_assignment(task)
      previous = task.persisted? ? task.assignee_id_was : nil
      yield
      TaskAssignment.notify(task, previous_assignee_id: previous, actor: Current.user)
    end
end
