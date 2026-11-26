# A Markdown comment on a task or in the thread of a change, stored exactly
# as written (spec comments). It belongs to exactly one of them, which the
# database checks as well (add-change-conversation design.md, decision 7).
class Comment < ApplicationRecord
  MAX_ATTACHMENTS = 10
  ATTACHMENT_POLICY = UploadPolicy.new(
    types: %w[image/png image/jpeg image/gif image/webp application/pdf text/plain text/csv application/zip],
    max_size: 10.megabytes
  )

  belongs_to :task, optional: true
  belongs_to :change, optional: true
  belongs_to :author, class_name: "User"
  has_many_attached :attachments

  scope :kept, -> { where(deleted_at: nil) }
  # Written by people, as opposed to agents.
  scope :by_people, -> { where.not(author_id: Agent.select(:user_id)) }
  # With what CommentSerializer shows of each.
  scope :for_listing, -> { includes(author: [ :agent, { avatar_attachment: :blob } ], attachments_attachments: :blob) }

  validates :body, presence: true, length: { maximum: 10_000 }
  validate :on_a_task_or_a_change

  # The project of its task or change.
  def project_id
    (task || change).project_id
  end

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
    def on_a_task_or_a_change
      errors.add(:base, :task_or_change) unless [ task_id, change_id ].compact.one?
    end

    # Plain text that is named .csv is stored as CSV; every other type is the
    # sniffed one.
    def detected_type(file)
      type = UploadPolicy.sniff(file)
      type == "text/plain" && File.extname(file.original_filename.to_s).casecmp?(".csv") ? "text/csv" : type
    end
end
