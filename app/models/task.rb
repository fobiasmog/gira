# A task (spec tasks). Every task is in a column; root tasks are ordered
# within their column and change, and subtasks hang off exactly one root task
# and belong to its change (spec changes, "Tasks in a change").
class Task < ApplicationRecord
  KEY_FORMAT = /\A[A-Z][A-Z0-9]*-(\d+)\z/

  belongs_to :project
  belongs_to :creator, class_name: "User"
  belongs_to :assignee, class_name: "User", optional: true
  belongs_to :status
  belongs_to :parent, class_name: "Task", optional: true
  belongs_to :change, optional: true
  belongs_to :label, optional: true
  has_many :subtasks, -> { kept.order(:id) }, class_name: "Task", foreign_key: :parent_id, inverse_of: :parent
  has_many :comments, dependent: :destroy

  # Contiguous positions from 0 among the root tasks of one column within one
  # change (or none).
  acts_as_list scope: %i[project_id status_id change_id parent_id], top_of_list: 0, add_new_at: :bottom

  scope :kept, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :roots, -> { where(parent_id: nil) }
  scope :not_done, -> { left_joins(:status).where(statuses: { done: [ false, nil ] }) }
  scope :done, -> { joins(:status).where(statuses: { done: true }) }
  # Boards and change lists: by column order, then position in the column.
  scope :in_column_order, -> { joins(:status).order("statuses.position", :position) }

  validates :title, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 100_000 }
  validate :references_belong_to_project
  validate :assignee_is_member, if: :assignee_id_changed?
  validate :change_is_open, if: :change_id_changed?
  validate :subtask_follows_its_card, if: :change_id_changed?
  validate :card_of_tasks_md_stays, if: :change_id_changed?, on: :update
  validate :parent_is_a_root_task, if: :parent_id_changed?
  validate :archived_tasks_are_read_only, on: :update

  before_validation :default_to_first_column, on: :create
  before_validation :take_parents_change, if: -> { parent && (new_record? || parent_id_changed?) }
  before_create :assign_number
  before_save :track_completion, if: :status_id_changed?
  after_update :move_subtasks_with_card, if: -> { root? && saved_change_to_change_id? }

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

  # Archives the task: it leaves the board and every list, and stays
  # readable in the project's archive.
  def archive!
    transaction do
      remove_from_list
      update_columns(archived_at: Time.current, position: nil, updated_at: Time.current)
    end
  end

  private
    # Only when no column was named: an unknown id must fail validation.
    def default_to_first_column
      self.status = project&.first_status if status_id.nil?
    end

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
      %i[status label change parent].each do |name|
        next if self[:"#{name}_id"].nil?

        record = public_send(name)
        errors.add(name, :invalid) if record.nil? || record.project_id != project_id
      end
    end

    # A deleted agent keeps its membership but takes no new work (spec
    # agents, "Delete an agent").
    def assignee_is_member
      return unless assignee_id

      if !project.memberships.exists?(user_id: assignee_id)
        errors.add(:assignee, :not_a_member)
      elsif Agent.deleted.exists?(user_id: assignee_id)
        errors.add(:assignee, :deleted)
      end
    end

    # No task is put into an archived change, a subtask included; tasks
    # already in one stay there.
    def change_is_open
      errors.add(:change, :archived) if change&.archived?
    end

    def subtask_follows_its_card
      errors.add(:change, :subtask) if parent && change_id != parent.change_id
    end

    # tasks.md owns the card: removing its section and importing again is
    # the way out (replace-sprints-with-changes design.md, decision 3).
    def card_of_tasks_md_stays
      errors.add(:change, :in_tasks_md) if in_tasks_md_in_database
    end

    def take_parents_change
      self.change_id = parent.change_id
    end

    # Archived subtasks too, so that every task of a change carries its id.
    # Positions stay contiguous: the card's subtasks all move together.
    def move_subtasks_with_card
      Task.where(parent_id: id).update_all(change_id: change_id, updated_at: Time.current)
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
