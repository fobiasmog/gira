# A Markdown comment on a task, stored exactly as written (spec comments).
class Comment < ApplicationRecord
  MAX_ATTACHMENTS = 10
  ATTACHMENT_POLICY = UploadPolicy.new(
    types: %w[image/png image/jpeg image/gif image/webp application/pdf text/plain text/csv application/zip],
    max_size: 10.megabytes
  )

  belongs_to :task
  belongs_to :author, class_name: "User"
  has_many_attached :attachments

  scope :kept, -> { where(deleted_at: nil) }

  validates :body, presence: true, length: { maximum: 10_000 }

  # Checks uploads before anything is stored; a single refused file rejects
  # the whole comment with an error naming it.
  def attach_uploads(files)
    files = Array(files).compact_blank
    errors.add(:attachments, :too_many, count: MAX_ATTACHMENTS) if files.size > MAX_ATTACHMENTS

    files.each do |file|
      if (violation = ATTACHMENT_POLICY.violation(file))
        errors.add(:attachments, :"file_#{violation}", filename: file.original_filename)
      end
    end
    return false if errors.any?

    files.each do |file|
      attachments.attach(io: file, filename: file.original_filename, content_type: detected_type(file), identify: false)
    end
    true
  end

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  private
    # Plain text that is named .csv is stored as CSV; every other type is the
    # sniffed one.
    def detected_type(file)
      type = UploadPolicy.sniff(file)
      type == "text/plain" && File.extname(file.original_filename.to_s).casecmp?(".csv") ? "text/csv" : type
    end
end
