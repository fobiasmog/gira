class CommentSerializer
  include Rails.application.routes.url_helpers

  def initialize(comment)
    @comment = comment
  end

  def as_json(*)
    {
      id: @comment.id,
      body: @comment.body,
      author: UserSerializer.new(@comment.author).card,
      created_at: @comment.created_at,
      updated_at: @comment.updated_at,
      attachments: @comment.attachments.map { |attachment| attachment_json(attachment.blob) }
    }
  end

  private
    def attachment_json(blob)
      signed_id = blob.signed_id
      {
        filename: blob.filename.to_s,
        byte_size: blob.byte_size,
        content_type: blob.content_type,
        url: file_path(signed_id),
        preview_url: (file_path(signed_id, variant: "preview") if FileVariant.preview?(blob))
      }
    end
end
