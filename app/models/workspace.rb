# The workspace of a change (spec agent-workspaces; add-runners-and-workspaces
# design.md, decision 3): the git worktree, on one runner's machine, where any
# agent working on the change continues from the same files and, through the
# session of its stint, the same conversation. The change owns it, not the
# agent, so it stays through releases and handovers.
#
# It is active from when it is recorded until its change is archived; then
# its runner removes it, or keeps it while it holds uncommitted changes.
# Removed is final. Only its runner reports on it.
class Workspace < ApplicationRecord
  STATES = %w[active kept removed].freeze
  # States a runner reports, once the change is archived.
  FINAL_STATES = %w[kept removed].freeze
  PATH_LIMIT = 1_000
  BRANCH_LIMIT = 255
  COMMIT_FORMAT = /\A\h{40}\z/

  belongs_to :change
  belongs_to :runner

  scope :active, -> { where(state: "active") }
  # The workspaces of archived changes that are still on disk: what their
  # runner has to remove.
  scope :to_remove, -> { where(state: %w[active kept]).joins(:change).merge(Change.archived) }
  # Active workspaces on any runner but runner, or on any runner when it is
  # nil: the changes a take or a lease of runner must leave alone.
  scope :held_elsewhere, ->(runner) { runner ? active.where.not(runner_id: runner.id) : active }

  validates :path, presence: true, length: { maximum: PATH_LIMIT }
  validates :branch, presence: true, length: { maximum: BRANCH_LIMIT }
  validates :state, inclusion: { in: STATES }
  validates :head_commit, format: { with: COMMIT_FORMAT }, allow_nil: true
  validates :uncommitted, inclusion: { in: [ true, false ] }, if: :checkpointing
  validate :active_for_checkpoint, if: :checkpointing

  # Set while a checkpoint is saved, which only an active workspace takes.
  attr_accessor :checkpointing

  normalizes :head_commit, with: ->(commit) { commit.downcase }

  # Records the workspace of change, an open change, on runner (spec
  # agent-workspaces, "Workspace of a change"), with the change's base branch.
  # The same path and branch again change nothing; another path or branch
  # is a validation error. A workspace of another runner is not found.
  def self.record!(change:, runner:, path:, branch:)
    change.project.with_lock do
      existing = change.reload.workspace
      raise ActiveRecord::RecordNotFound if existing && existing.runner_id != runner.id
      next create!(change:, runner:, path:, branch:, base_branch: change.base_branch) unless existing

      existing.errors.add(:path, :fixed) unless existing.path == path
      existing.errors.add(:branch, :fixed) unless existing.branch == branch
      raise ActiveRecord::RecordInvalid, existing if existing.errors.any?

      existing
    end
  end

  def active?
    state == "active"
  end

  # The latest checkpoint (spec agent-workspaces, "Checkpoints"): the commit
  # its branch is at, and whether the worktree holds uncommitted changes.
  def checkpoint!(head_commit:, uncommitted:)
    assign_attributes(head_commit: head_commit.to_s, uncommitted:, checkpoint_at: Time.current)
    self.checkpointing = true
    save!
  ensure
    self.checkpointing = false
  end

  # Marks a workspace of an archived change as removed, or as kept because
  # its worktree holds uncommitted changes (spec agent-workspaces, "Removing
  # workspaces"). Removed is final; marking it removed again changes nothing.
  def mark!(state)
    state = state.to_s
    return self if state == "removed" && self.state == "removed"

    errors.clear
    errors.add(:state, :inclusion) unless FINAL_STATES.include?(state)
    errors.add(:base, :change_open) unless change.archived?
    errors.add(:state, :removed) if self.state == "removed"
    raise ActiveRecord::RecordInvalid, self if errors.any?

    update!(state:)
  end

  private
    def active_for_checkpoint
      errors.add(:base, :not_active) unless active?
    end
end
