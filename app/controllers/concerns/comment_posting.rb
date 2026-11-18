# Posting a comment on a task or a change (spec comments): the body from
# JSON or multipart, and attachments from multipart, all refused together
# when one of them is.
module CommentPosting
  private
    def post_comment(comments)
      comment = comments.new(body: params[:body].to_s, author: Current.user)
      comment.validate
      if comment.errors.none? && comment.attach_uploads(params[:attachments]) && comment.save
        render json: CommentSerializer.new(comment), status: :created
      else
        render_validation_errors comment
      end
    end
end
