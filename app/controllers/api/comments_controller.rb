# Editing and deleting one's own comments, on tasks and on changes. Someone
# else's comment, or one in a project the user cannot see, is a 404.
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
      projects = Current.projects.select(:id)
      own = Comment.kept.where(author: Current.user).left_joins(:task, :change)
      @comment = own.where(tasks: { project_id: projects }).or(own.where(changes: { project_id: projects })).find(params[:id])
    end
end
