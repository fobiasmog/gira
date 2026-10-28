# Comments on a task (spec comments). Archived tasks are read-only.
class Api::Projects::Tasks::CommentsController < Api::BaseController
  include ProjectScoped
  allow_token_access only: %i[ index create ]
  before_action :set_task

  def index
    comments = @task.comments.kept.order(created_at: :desc, id: :desc).includes(:author, attachments_attachments: :blob)
    render json: comments.map { |comment| CommentSerializer.new(comment) }
  end

  def create
    raise ActiveRecord::RecordInvalid, @task.tap { |t| t.errors.add(:base, :archived) } if @task.archived?

    comment = @task.comments.new(body: params[:body].to_s, author: Current.user)
    comment.validate
    if comment.errors.none? && comment.attach_uploads(params[:attachments]) && comment.save
      render json: CommentSerializer.new(comment), status: :created
    else
      render_validation_errors comment
    end
  end

  private
    def set_task
      @task = @project.tasks.find(params[:task_id])
    end
end
