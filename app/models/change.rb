# A change (spec changes): one piece of work in a project, with its own tasks
# and its own board, named by its OpenSpec name and archived when it is done.
# A project holds many open changes at once, and none of them is "active".
#
# An import (spec openspec-changes) keeps on the change the marked tasks.md
# text it last returned, and who imported it when; all three stay nil until
# the first import (replace-sprints-with-changes design.md, decision 1).
class Change < ApplicationRecord
  NAME_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  NAME_LIMIT = 100
  # A path or query value made only of digits names a change by id;
  # anything else names an open change by its name (spec changes, "Open a
  # change").
  ID_FORMAT = /\A\d+\z/

  belongs_to :project
  belongs_to :imported_by, class_name: "User", optional: true
  has_many :tasks, dependent: nil

  scope :kept, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  validates :name, presence: true, length: { maximum: NAME_LIMIT }, format: { with: NAME_FORMAT, allow_blank: true }
  # Archived changes give their name up (design.md, decision 1); the partial
  # unique index backs this up.
  validates :name, uniqueness: { scope: :project_id, conditions: -> { kept } }, unless: :archived?

  def self.valid_name?(name)
    name.is_a?(String) && name.length <= NAME_LIMIT && NAME_FORMAT.match?(name)
  end

  # By id, or an open change by name.
  def self.find_by_ref!(ref)
    ref = ref.to_s
    ID_FORMAT.match?(ref) ? find(ref) : kept.find_by!(name: ref)
  end

  # Root, non-archived task counts per column id and in total, for many
  # changes in one query: change id => { by_status:, total: }.
  def self.task_counts_for(changes)
    rows = Task.kept.roots.where(change_id: changes.map(&:id)).group(:change_id, :status_id).count
    changes.to_h do |change|
      by_status = rows.filter_map { |(change_id, status_id), count| [ status_id, count ] if change_id == change.id }.to_h
      [ change.id, { by_status:, total: by_status.values.sum } ]
    end
  end

  def archived?
    archived_at.present?
  end

  # Archiving an archived change leaves it as it is, archive time included.
  def archive!
    update!(archived_at: Time.current) unless archived?
  end

  def task_counts
    self.class.task_counts_for([ self ]).fetch(id)
  end

  # The marked text as last returned, with the checkbox of every item whose
  # subtask is done now checked (spec openspec-changes, "Read a change"), or
  # nil for a change never imported.
  def current_tasks_text
    return if tasks_text.nil?

    text = Change::TasksText.new(tasks_text)
    done = tasks.kept.where.not(parent_id: nil).done.pluck(:number).to_set
    text.render(checked: text.items.filter_map { |item| item.line if item.mark && done.include?(item.mark) })
  end
end
