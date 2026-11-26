# Comments on a task (spec comments), newest first. Archived tasks are
# read-only.
class Api::Projects::Tasks::CommentsController < Api::BaseController
  include ProjectScoped
  include CommentPosting
  allow_token_access only: %i[ index create ]
  before_action :set_task

  def index
    comments = @task.comments.kept.order(created_at: :desc, id: :desc).for_listing
    render json: comments.map { |comment| CommentSerializer.new(comment) }
  end

  def create
    raise ActiveRecord::RecordInvalid, @task.tap { |t| t.errors.add(:base, :archived) } if @task.archived?

    post_comment @task.comments
  end

  private
    def set_task
      @task = @project.tasks.find_by_ref!(params[:task_id])
    end
end
