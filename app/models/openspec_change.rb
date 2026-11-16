# An OpenSpec change pushed into a project (spec openspec-changes). Its
# tasks.md sections are cards and its items their subtasks, and the cards
# are grouped under a milestone titled with the change's name. The marked
# tasks text it last returned is kept for reading the change back.
class OpenspecChange < ApplicationRecord
  NAME_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  belongs_to :project
  belongs_to :milestone
  belongs_to :imported_by, class_name: "User"
  has_many :tasks, dependent: :nullify

  validates :name, presence: true, length: { maximum: 100 }, format: { with: NAME_FORMAT, allow_blank: true },
    uniqueness: { scope: :project_id }

  # The marked text as last returned, with the checkbox of every item whose
  # subtask is done now checked (spec openspec-changes, "Read a change").
  def current_tasks_text
    text = OpenspecChange::TasksText.new(tasks_text)
    done = tasks.kept.where.not(parent_id: nil).done.pluck(:number).to_set
    text.render(checked: text.items.filter_map { |item| item.line if item.mark && done.include?(item.mark) })
  end
end
