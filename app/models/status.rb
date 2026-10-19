# A board column (spec project-board). Positions are contiguous from 0, and
# the last column is the done column (see Board).
class Status < ApplicationRecord
  belongs_to :project
  has_many :tasks, dependent: nil # deleting a column moves its tasks to the backlog (Board#delete_column)

  acts_as_list scope: :project, top_of_list: 0, add_new_at: :bottom

  validates :title, presence: true, length: { maximum: 50 }
end
