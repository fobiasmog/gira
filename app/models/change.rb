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
#
# A change has requests for its steps (ChangeRequest), at most one of them
# open, and at most one agent, picked or on the change; an agent is on at
# most one open change, and its change is blocked while its context is full
# (add-change-requests design.md, decisions 2, 7, 8, 10 and 13). Picking,
# releasing, blocking and archiving run under the project's lock.
#
# A change has a base branch, main for every change for now, and at most one
# workspace on one runner (Workspace). The agent on it has a session for its
# stint, a UUID that the worker continues the stint's conversation by; it
# ends with the stint (add-runners-and-workspaces design.md, decisions 3 and
# 8).
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
  # Every change's work starts from it for now; nobody chooses another.
  BASE_BRANCH = "main"

  belongs_to :project
  belongs_to :imported_by, class_name: "User", optional: true
  has_many :tasks, dependent: nil
  has_many :files, class_name: "ChangeFile", dependent: :delete_all
  has_many :events, -> { order(:created_at, :id) }, class_name: "ChangeEvent", dependent: :delete_all, inverse_of: :change
  has_many :comments, dependent: :destroy
  has_many :requests, class_name: "ChangeRequest", dependent: :delete_all
  has_one :open_request, -> { unfinished }, class_name: "ChangeRequest", inverse_of: :change
  has_one :workspace, dependent: :delete
  # The agent's user, picked or on the change.
  belongs_to :agent, class_name: "User", optional: true

  scope :kept, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  # The changes an agent is on, open or archived.
  scope :on_by, ->(agent) { where(agent_id: agent.id).where.not(agent_taken_at: nil) }

  validates :name, presence: true, length: { maximum: NAME_LIMIT }, format: { with: NAME_FORMAT, allow_blank: true }
  # Archived changes give their name up (design.md, decision 1); the partial
  # unique index backs this up.
  validates :name, uniqueness: { scope: :project_id, conditions: -> { kept } }, unless: :archived?
  validates :idea, length: { maximum: IDEA_LIMIT }
  validates :phase, inclusion: { in: PHASES }
  validate :idea_fixed_once_exploring, if: :will_save_change_to_idea?, on: :update
  validate :archived_changes_are_read_only, on: :update
  validate :agent_of_the_project, if: -> { agent_id && will_save_change_to_agent_id? }
  validate :agent_kept_while_on, if: :will_save_change_to_agent_id?, on: :update

  # No idea is an empty idea.
  normalizes :idea, with: ->(idea) { idea.presence }

  attribute :base_branch, default: BASE_BRANCH
  attr_readonly :base_branch

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

  # The ids of the given open changes that are waiting for people (spec
  # changes, "Waiting for people"), in one query: those that are blocked,
  # and those with no open request whose newest comment was written by an
  # agent.
  def self.waiting_for_people(changes)
    open = changes.reject(&:archived?)
    return Set.new if open.empty?

    newest = Comment.kept.where(change_id: open.map(&:id))
      .select("DISTINCT ON (comments.change_id) comments.change_id, comments.author_id")
      .order(:change_id, created_at: :desc, id: :desc)
    asked = Comment.unscoped.from(newest, :newest)
      .joins("JOIN agents ON agents.user_id = newest.author_id")
      .where("NOT EXISTS (SELECT 1 FROM change_requests WHERE change_requests.change_id = newest.change_id AND change_requests.state IN (?))", ChangeRequest::OPEN_STATES)
      .pluck("newest.change_id")
    open.select(&:blocked?).to_set(&:id) | asked
  end

  # Under the project's lock, picks agent, a user, or no agent for any free
  # agent, while no agent is on the change (spec change-requests, "Agent of
  # a change"). Picking asks for no step.
  def pick_agent!(agent)
    project.with_lock do
      update!(agent:)
    end
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

  # Whether its agent is on it rather than picked.
  def agent_on?
    agent_taken_at.present?
  end

  def blocked?
    agent_blocked_at.present?
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

  # Under the project's lock, cancels the open request as by and archives
  # the change, which frees its agent (spec changes, "Archive a change";
  # decision 10). Archiving an archived change leaves it as it is, archive
  # time included.
  def archive!(by: nil)
    project.with_lock do
      reload
      next if archived?

      open_request&.close!("cancelled", by:)
      update!(archived_at: Time.current, agent_session_id: nil)
    end
  end

  # Under the project's lock, gives the agent on the change a session for
  # its stint when it has none (spec agent-workspaces, "Session of a
  # stint"), as for a change it was on before sessions existed.
  def give_session!
    project.with_lock do
      reload
      update!(agent_session_id: SecureRandom.uuid) if agent_on? && !archived? && agent_session_id.nil?
    end
  end

  # Under the project's lock, releases the agent as by (spec change-requests,
  # "Release an agent"): cancels the taken request, ends the block, leaves
  # the change with no agent and records the release. A change with no agent
  # is left as it is.
  def release_agent!(by:)
    project.with_lock do
      reload
      next if agent_id.nil?

      released = agent
      open_request.close!("cancelled", by:) if open_request&.state == "taken"
      update!(agent: nil, agent_taken_at: nil, agent_blocked_at: nil, agent_session_id: nil)
      events.create!(kind: "release", actor: by, agent: released)
    end
  end

  # Under the project's lock, blocks the open change of project that agent
  # is on, because its context is full (spec change-requests, "Full
  # context"; decision 13), and records the block once. Returns whether the
  # agent is blocked: false when it is on no open change of project.
  def self.block_for_full_context!(project:, agent:)
    project.with_lock do
      change = project.project_changes.kept.on_by(agent).first
      next false unless change

      unless change.blocked?
        change.update!(agent_blocked_at: Time.current)
        change.events.create!(kind: "block", actor: agent)
      end
      true
    end
  end

  # A reply request for comment, a person's comment just posted on the
  # change, when the change is open, past Idea and has no open request
  # (spec change-requests, "Reply requests"; decision 7). Called under the
  # project's lock.
  def ask_reply_after(comment)
    return if comment.author.agent? || archived? || phase == "idea" || requests.unfinished.exists?

    requests.create!(kind: "reply", requested_by: comment.author)
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

    # An agent of the change's project that is not deleted.
    def agent_of_the_project
      agent_member = Agent.kept.where(user_id: agent_id).exists? && project.memberships.exists?(user_id: agent_id)
      errors.add(:agent, :not_an_agent) unless agent_member
    end

    # Once an agent is on the change, only releasing it (which clears
    # agent_taken_at with it) changes the agent.
    def agent_kept_while_on
      errors.add(:agent, :on_the_change) if agent_taken_at_in_database && agent_taken_at
    end
end
