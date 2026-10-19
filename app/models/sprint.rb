# A time-boxed sprint (spec sprints). At most one per project is active,
# enforced by a partial unique index and by activating inside a project lock.
class Sprint < ApplicationRecord
  belongs_to :project
  has_many :tasks, dependent: nil

  scope :kept, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :available, -> { kept.where(starts_on: Date.current..).or(kept.where(active: true)) }

  validates :title, presence: true, length: { maximum: 100 }
  validates :starts_on, :ends_on, presence: true
  validate :ends_on_or_after_start

  def archived?
    archived_at.present?
  end

  # Makes this the project's only active sprint.
  def activate!
    project.with_lock do
      project.sprints.where(active: true).where.not(id: id).update_all(active: false, updated_at: Time.current)
      update!(active: true)
    end
  end

  # Copies every root, non-archived task of this sprint that is not in the
  # done column into the target sprint, linking each copy to its original.
  # Done tasks stay only here.
  def carry_over_to(target)
    raise ArgumentError, "target sprint belongs to another project" unless target.project_id == project_id

    transaction do
      tasks.kept.roots.not_done.order(:status_id, :position).each do |task|
        project.tasks.create!(
          task.slice(:title, :description, :creator_id, :assignee_id, :status_id, :milestone_id, :label_id, :deadline, :important)
            .merge(sprint: target, origin_task: task)
        )
      end
    end
  end

  # Archives the sprint, first carrying unfinished tasks over to `carry_to`
  # when given. An archived sprint is never active.
  def archive!(carry_to: nil)
    transaction do
      carry_over_to(carry_to) if carry_to
      update!(archived_at: Time.current, active: false)
    end
  end

  # Non-archived task counts per column id, plus the total.
  def task_counts
    by_status = tasks.kept.group(:status_id).count
    { by_status: by_status.transform_keys { |id| id || "backlog" }, total: by_status.values.sum }
  end

  private
    def ends_on_or_after_start
      errors.add(:ends_on, :before_start) if starts_on && ends_on && ends_on < starts_on
    end
end
