class Label < ApplicationRecord
  belongs_to :project
  has_many :tasks, dependent: :nullify

  validates :title, presence: true, length: { maximum: 30 },
    uniqueness: { scope: :project_id, case_sensitive: false }
end
