# A change (spec changes): one piece of work in a project, with its own tasks
# and its own board, named by its OpenSpec name and archived when it is done.
# A project holds many open changes at once, and none of them is "active".
#
# An import (spec openspec-changes) keeps on the change the marked tasks.md
# text it last returned, and who imported it when; all three stay nil until
# the first import (replace-sprints-with-changes design.md, decision 1). It
# also keeps the other OpenSpec files of the last import (ChangeFile).
#
# A change has an idea, fixed once exploring starts, a phase, a history of
# phase moves and imports (ChangeEvent), and a thread of comments
# (add-change-conversation design.md, decisions 1, 2, 4, 7 and 8). Done is
# never stored: it is reported while every card of a change in Implementing
# is in the done column (#phase_reported).
class Change < ApplicationRecord
  NAME_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  NAME_LIMIT = 100
  IDEA_LIMIT = 100_000
  # Stored phases, in order; Done follows them and is only ever reported.
  PHASES = %w[idea exploring proposed implementing].freeze
  DONE = "done"
  # A path or query value made only of digits names a change by id;
  # anything else names an open change by its name (spec changes, "Open a
  # change").
  ID_FORMAT = /\A\d+\z/

  belongs_to :project
  belongs_to :imported_by, class_name: "User", optional: true
  has_many :tasks, dependent: nil
  has_many :files, class_name: "ChangeFile", dependent: :delete_all
  has_many :events, -> { order(:created_at, :id) }, class_name: "ChangeEvent", dependent: :delete_all, inverse_of: :change
  has_many :comments, dependent: :destroy

  scope :kept, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  validates :name, presence: true, length: { maximum: NAME_LIMIT }, format: { with: NAME_FORMAT, allow_blank: true }
  # Archived changes give their name up (design.md, decision 1); the partial
  # unique index backs this up.
  validates :name, uniqueness: { scope: :project_id, conditions: -> { kept } }, unless: :archived?
  validates :idea, length: { maximum: IDEA_LIMIT }
  validates :phase, inclusion: { in: PHASES }
  validate :idea_fixed_once_exploring, if: :will_save_change_to_idea?, on: :update
  validate :archived_changes_are_read_only, on: :update

  # No idea is an empty idea.
  normalizes :idea, with: ->(idea) { idea.presence }

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

  # The ids of the given open changes whose newest comment was written by an
  # agent (spec changes, "Waiting for people"), in one query.
  def self.waiting_for_people(changes)
    ids = changes.reject(&:archived?).map(&:id)
    return Set.new if ids.empty?

    newest = Comment.kept.where(change_id: ids)
      .select("DISTINCT ON (comments.change_id) comments.change_id, comments.author_id")
      .order(:change_id, created_at: :desc, id: :desc)
    Comment.unscoped.from(newest, :newest)
      .joins("JOIN agents ON agents.user_id = newest.author_id")
      .pluck("newest.change_id").to_set
  end

  # The phase to report for a change in stored phase, given its task counts
  # and its project's done column: Done while it is in Implementing and has
  # cards, all of them in the done column.
  def self.reported_phase(phase, task_counts, done_status_id)
    total = task_counts[:total]
    done = task_counts[:by_status].fetch(done_status_id, 0)
    phase == "implementing" && total.positive? && done == total ? DONE : phase
  end

  def archived?
    archived_at.present?
  end

  def phase_reported(task_counts: self.task_counts, done_status_id: project.done_status&.id)
    self.class.reported_phase(phase, task_counts, done_status_id)
  end

  def waiting_for_people?
    self.class.waiting_for_people([ self ]).include?(id)
  end

  # Moves the change to phase and records who did it, saving any other
  # attribute assigned with it. Moving to the phase it is in records
  # nothing; Done, or an unknown phase, is a validation error on phase.
  def move_to!(phase, by:)
    transaction do
      self.phase = phase
      moved = will_save_change_to_phase?
      save!
      events.create!(kind: "phase", actor: by, phase: self.phase) if moved
    end
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

  private
    # Later corrections go into the thread, where an agent sees them as new
    # input (add-change-conversation design.md, decision 1).
    def idea_fixed_once_exploring
      errors.add(:idea, :fixed) unless phase_in_database == "idea"
    end

    # Archiving itself is the last update of a change.
    def archived_changes_are_read_only
      errors.add(:base, :archived) if archived_at_in_database.present?
    end
end
