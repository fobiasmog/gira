# Delivers stored files only to users allowed to see them (design.md,
# Decision 7): an avatar to its owner and to members of the projects the
# request may reach, a comment attachment to members of the comment's project
# (with an API token, only within the token's project). Anything else is a
# 404. Files are always downloads (Content-Disposition: attachment) and never
# sniffed by browsers.
class FilesController < ApplicationController
  include ApiTokenAuthentication
  allow_token_access only: :show

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
    # Not a JSON endpoint: token failures are bare statuses.
    def render_token_error(status, _code)
      head status
    end

    def visible?(attachment)
      case [ attachment.record_type, attachment.name ]
      in [ "User", "avatar" ]
        attachment.record_id == Current.user.id || Membership.where(project: Current.projects).exists?(user_id: attachment.record_id)
      in [ "Comment", "attachments" ]
        comment = attachment.record
        comment.deleted_at.nil? && Current.projects.exists?(comment.task.project_id)
      else
        false
      end
    end
end
