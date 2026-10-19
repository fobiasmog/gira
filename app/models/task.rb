# A task (spec tasks). Root tasks are ordered within their column (or the
# backlog) and sprint; subtasks hang off exactly one root task.
class Task < ApplicationRecord
  KEY_FORMAT = /\A[A-Z][A-Z0-9]*-(\d+)\z/

  belongs_to :project
  belongs_to :creator, class_name: "User"
  belongs_to :assignee, class_name: "User", optional: true
  belongs_to :status, optional: true
  belongs_to :parent, class_name: "Task", optional: true
  belongs_to :sprint, optional: true
  belongs_to :milestone, optional: true
  belongs_to :label, optional: true
  belongs_to :origin_task, class_name: "Task", optional: true
  has_many :subtasks, -> { kept.order(:id) }, class_name: "Task", foreign_key: :parent_id, inverse_of: :parent
  has_many :comments, dependent: :destroy

  # Contiguous positions from 0 among the tasks shown together: the root
  # tasks of one column (or the backlog) within one sprint (or none).
  acts_as_list scope: %i[project_id status_id sprint_id parent_id], top_of_list: 0, add_new_at: :bottom

  scope :kept, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :roots, -> { where(parent_id: nil) }
  scope :on_board, -> { where.not(status_id: nil) }
  scope :in_backlog, -> { where(status_id: nil) }
  scope :not_done, -> { left_joins(:status).where(statuses: { done: [ false, nil ] }) }

  validates :title, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 100_000 }
  validate :references_belong_to_project
  validate :assignee_is_member, if: :assignee_id_changed?
  validate :milestone_is_not_deleted, if: :milestone_id_changed?
  validate :sprint_is_open_and_task_is_root, if: :sprint_id_changed?
  validate :parent_is_a_root_task, if: :parent_id_changed?
  validate :archived_tasks_are_read_only, on: :update

  before_create :assign_number
  before_save :track_completion, if: :status_id_changed?

  def self.find_by_ref!(ref)
    if (number = ref.to_s[KEY_FORMAT, 1])
      find_by!(number: number)
    else
      find(ref)
    end
  end

  def key
    "#{project.short_name}-#{number}"
  end

  def root?
    parent_id.nil?
  end

  def archived?
    archived_at.present?
  end

  def done?
    status&.done? || false
  end

  # Archives the task: it leaves the board, backlog and every list, and stays
  # readable in the project's archive.
  def archive!
    transaction do
      remove_from_list
      update_columns(archived_at: Time.current, position: nil, updated_at: Time.current)
    end
  end

  private
    def assign_number
      self.number ||= project.next_task_number!
    end

    def track_completion
      self.completed_at = done? ? Time.current : nil
    end

    # Ids supplied by clients are checked here, so no endpoint can attach a
    # record of another project (design.md, Decision 7). An unknown id is
    # rejected the same way as a foreign one.
    def references_belong_to_project
      %i[status milestone label sprint parent].each do |name|
        next if self[:"#{name}_id"].nil?

        record = public_send(name)
        errors.add(name, :invalid) if record.nil? || record.project_id != project_id
      end
    end

    def assignee_is_member
      errors.add(:assignee, :not_a_member) if assignee_id && !project.memberships.exists?(user_id: assignee_id)
    end

    def milestone_is_not_deleted
      errors.add(:milestone, :deleted) if milestone&.deleted?
    end

    def sprint_is_open_and_task_is_root
      return unless sprint

      errors.add(:sprint, :archived) if sprint.archived?
      errors.add(:sprint, :subtask) if parent_id
    end

    def parent_is_a_root_task
      return unless parent

      errors.add(:parent, :nested) unless parent.root?
      errors.add(:parent, :archived) if parent.archived?
      errors.add(:parent, :nested) if subtasks.exists?
    end

    def archived_tasks_are_read_only
      errors.add(:base, :archived) if archived_at_was.present?
    end
end
