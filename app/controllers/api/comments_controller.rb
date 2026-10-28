# Editing and deleting one's own comments. Someone else's comment, or one in
# a project the user cannot see, is a 404.
class Api::CommentsController < Api::BaseController
  allow_token_access only: %i[ update destroy ]
  before_action :set_comment

  def update
    @comment.update!(body: params[:body].to_s)
    render json: CommentSerializer.new(@comment)
  end

  def destroy
    @comment.soft_delete!
    head :no_content
  end

  private
    def set_comment
      @comment = Comment.kept.where(author: Current.user)
        .joins(:task).where(tasks: { project_id: Current.projects.select(:id) })
        .find(params[:id])
    end
end
