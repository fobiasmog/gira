class Milestone < ApplicationRecord
  belongs_to :project
  has_many :tasks, dependent: nil # tasks keep the reference while deleted, so recovering restores the grouping

  scope :kept, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  validates :title, presence: true, length: { maximum: 100 }

  def deleted?
    deleted_at.present?
  end

  def delete!
    update!(deleted_at: Time.current)
  end

  def recover!
    update!(deleted_at: nil)
  end

  # Non-archived tasks, and how many of them are in the done column.
  def progress
    tasks = self.tasks.kept
    { total: tasks.count, done: tasks.joins(:status).where(statuses: { done: true }).count }
  end
end
