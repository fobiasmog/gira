# The thread of a change (spec comments, "Comment on a change";
# add-change-conversation design.md, decision 7), oldest first, as a
# conversation reads. Archived changes keep their thread and take no more.
class Api::Projects::Changes::CommentsController < Api::BaseController
  include ProjectScoped
  include CommentPosting
  allow_token_access only: %i[ index create ]
  before_action :set_change

  def index
    comments = @change.comments.kept.order(:created_at, :id).for_listing
    render json: comments.map { |comment| CommentSerializer.new(comment) }
  end

  def create
    raise ActiveRecord::RecordInvalid, @change.tap { |c| c.errors.add(:base, :archived) } if @change.archived?

    post_comment @change.comments
  end

  private
    def set_change
      @change = @project.project_changes.find_by_ref!(params[:change_id])
    end
end
