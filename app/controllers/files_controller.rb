# Delivers stored files only to users allowed to see them (design.md,
# Decision 7): an avatar to its owner and teammates, a comment attachment to
# members of the comment's project. Anything else is a 404. Files are always
# downloads (Content-Disposition: attachment) and never sniffed by browsers.
class FilesController < ApplicationController
  def show
    blob = ActiveStorage::Blob.find_signed!(params[:signed_id])
    attachment = blob.attachments.find { |candidate| visible?(candidate) } or raise ActiveRecord::RecordNotFound
    file = FileVariant.for(attachment, params[:variant])

    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Cache-Control"] = "private, max-age=3600"
    send_data file.download, filename: file.filename.to_s, type: file.content_type, disposition: :attachment
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    raise ActiveRecord::RecordNotFound
  end

  private
    def visible?(attachment)
      case [ attachment.record_type, attachment.name ]
      in [ "User", "avatar" ]
        attachment.record_id == Current.user.id || Current.user.teammates.exists?(attachment.record_id)
      in [ "Comment", "attachments" ]
        comment = attachment.record
        comment.deleted_at.nil? && Current.user.projects.kept.exists?(comment.task.project_id)
      else
        false
      end
    end
end
