# Tasks (spec tasks; board and backlog listing from spec project-board).
class Api::Projects::TasksController < Api::BaseController
  include ProjectScoped
  allow_token_access only: %i[ index show create update destroy ]
  before_action :set_task, only: %i[ show update destroy ]

  VIEWS = %w[board backlog backlog_done archived].freeze

  # ?view=board (default): root tasks on the board: the active sprint's, or
  #   those in no sprint when none is active
  # ?view=backlog: open root tasks in no sprint, in column order
  # ?view=backlog_done: done root tasks in no sprint, most recently completed first
  # ?view=archived: archived tasks, newest first
  def index
    tasks = case params.fetch(:view, "board").presence_in(VIEWS)
    when "board" then board_tasks(@project)
    when "backlog" then @project.tasks.kept.roots.in_backlog.not_done.in_column_order
    when "backlog_done" then @project.tasks.kept.roots.in_backlog.done.order(Task.arel_table[:completed_at].desc.nulls_last, id: :desc)
    when "archived" then @project.tasks.archived.order(archived_at: :desc, id: :desc)
    else raise ActiveRecord::RecordNotFound
    end

    render json: TaskSerializer.cards(tasks.includes(:project))
  end

  def show
    render json: TaskSerializer.new(@task).detail
  end

  # A named sprint_id wins (null: no sprint). Otherwise a task created on a
  # column joins the active sprint, and one created without a column goes to
  # the first column in no sprint.
  def create
    task = @project.tasks.new(task_params.merge(status_id: params[:status_id], label_id: params[:label_id], creator: Current.user))
    task.sprint_id = params.key?(:sprint_id) ? params[:sprint_id] : (@project.active_sprint&.id if task.status_id)
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
      project.tasks.kept.roots.where(sprint_id: project.active_sprint&.id).in_column_order
    end

    # Runs the save and, only when it succeeds, notifies a newly assigned user.
    def track_assignment(task)
      previous = task.persisted? ? task.assignee_id_was : nil
      yield
      TaskAssignment.notify(task, previous_assignee_id: previous, actor: Current.user)
    end
end
