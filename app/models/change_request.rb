# A request for one step of a change (spec change-requests;
# add-change-requests design.md, decisions 1, 3, 5 and 7): explore, propose,
# implement, archive, or reply to comments. It is waiting until an agent
# takes it, then taken, then done, failed or cancelled; waiting and taken
# requests are open, and a change has at most one open request, which the
# partial unique index backs.
#
# Named ChangeRequest so that it never reads like a controller's request; in
# the API and the UI it is a request.
#
# Asking, taking, finishing and cancelling run under the project's lock, as
# every change to a change's request or agent does (decision 5). Refusals
# raise ActiveRecord::RecordInvalid with the errors on the request.
class ChangeRequest < ApplicationRecord
  KINDS = %w[explore propose implement archive reply].freeze
  # Kinds people ask for; reply requests come from comments only.
  ASKABLE_KINDS = (KINDS - %w[reply]).freeze
  STATES = %w[waiting taken done failed cancelled].freeze
  OPEN_STATES = %w[waiting taken].freeze
  OUTCOMES = %w[done failed].freeze

  belongs_to :change
  belongs_to :requested_by, class_name: "User"
  belongs_to :taken_by, class_name: "User", optional: true
  belongs_to :finished_by, class_name: "User", optional: true

  scope :unfinished, -> { where(state: OPEN_STATES) }
  scope :waiting, -> { where(state: "waiting") }
  scope :taken, -> { where(state: "taken") }
  scope :oldest_first, -> { order(:created_at, :id) }
  scope :in_project, ->(project) { joins(:change).where(changes: { project_id: project.id }) }

  # The outcome finish! was given, which its errors name.
  attr_reader :outcome

  validates :kind, inclusion: { in: KINDS }
  validates :state, inclusion: { in: STATES }

  class << self
    # Asks for a step of change as by (spec change-requests, "Ask for a
    # step"), with an optional comment posted as by's, which asks for no
    # reply. A waiting reply request gives way to it; any other open request,
    # or an archived change, refuses it.
    def ask!(change:, kind:, by:, comment: nil)
      change.project.with_lock do
        change.reload
        request = new(change:, kind: kind.to_s, requested_by: by)
        request.errors.add(:kind, :inclusion) unless ASKABLE_KINDS.include?(request.kind)
        request.errors.add(:base, :change_archived) if change.archived?
        open = change.requests.unfinished.first
        replaced = open if open&.kind == "reply" && open.state == "waiting"
        request.errors.add(:base, :open_request) if open && !replaced
        posted = request.new_comment(comment, by:) unless comment.nil?
        raise ActiveRecord::RecordInvalid, request if request.errors.any?

        # The request first, then its comment, as the thread reads them.
        replaced&.close!("cancelled", by:)
        request.save!
        posted&.save!
        request
      end
    end

    # The request an agent takes in project, or nil (spec change-requests,
    # "Take a request"; decision 3), the first of:
    # 1. its own taken request that is not finished, unless its change is
    #    blocked;
    # 2. the waiting request of the change it is on;
    # 3. when it is on no open change: the oldest waiting request of a
    #    change that has it picked;
    # 4. when it is on no open change: the oldest waiting request of a
    #    change with no agent.
    # Every take is the agent's check-in in project, whatever it returns.
    #
    # runner is that of the run token's lease the take is made with, or nil
    # for any other token: no step returns a request of a change whose
    # workspace is active on another runner, or on any runner for nil
    # (add-runners-and-workspaces design.md, decision 3). The returned
    # request's change has a session for the agent's stint.
    def take!(project:, agent:, runner: nil)
      project.with_lock do
        project.memberships.where(user_id: agent.id).update_all(checked_in_at: Time.current)
        elsewhere = Workspace.held_elsewhere(runner).select(:change_id)

        resumed = in_project(project).taken.where(taken_by: agent, changes: { agent_blocked_at: nil })
          .where.not(change_id: elsewhere).order(:taken_at, :id).first
        next resumed.tap { |request| request.change.give_session! } if resumed

        on = Change.kept.on_by(agent).first
        request = if on
          on.requests.waiting.where.not(change_id: elsewhere).first if on.project_id == project.id && !on.blocked?
        else
          queued(project, agent_id: agent.id, elsewhere:) || queued(project, agent_id: nil, elsewhere:)
        end
        request&.taken_by!(agent)
      end
    end

    private
      # The oldest waiting request of an open change of project whose agent
      # is picked as agent_id, or of one with no agent when it is nil, and
      # whose workspace is not elsewhere.
      def queued(project, agent_id:, elsewhere:)
        in_project(project).waiting.oldest_first
          .where(changes: { archived_at: nil, agent_id:, agent_taken_at: nil }).where.not(change_id: elsewhere).first
      end
  end

  def open?
    OPEN_STATES.include?(state)
  end

  # Finishes a request that by took as done or failed, posting comment as
  # by's (spec change-requests, "Finish a request"; decision 7). An archive
  # request done archives the change. Otherwise a person's comment posted
  # since the request was taken gets a reply request, asked for by the
  # author of the newest one.
  def finish!(by:, outcome:, comment:)
    change.project.with_lock do
      reload
      errors.add(:base, :not_taken) unless state == "taken" && taken_by_id == by.id
      @outcome = outcome
      errors.add(:outcome, :inclusion) unless OUTCOMES.include?(outcome)
      posted = new_comment(comment, by:)
      raise ActiveRecord::RecordInvalid, self if errors.any?

      # Finished first, then its comment, as the thread reads them.
      close!(outcome, by:)
      posted.save!
      if kind == "archive" && outcome == "done"
        change.archive!(by:)
      elsif (late = change.comments.kept.by_people.where("comments.created_at > ?", taken_at).order(created_at: :desc, id: :desc).first)
        change.requests.create!(kind: "reply", requested_by: late.author)
      end
      self
    end
  end

  # Cancels an open request as by (spec change-requests, "Cancel a
  # request"). A finished request stays as it is, and the change keeps its
  # agent either way.
  def cancel!(by:)
    change.project.with_lock do
      reload
      close!("cancelled", by:) if open?
      self
    end
  end

  # Marks a waiting request taken by agent; on its change's first request
  # the agent is on the change from now on, with a new session for its
  # stint. Taking an explore request moves a change in Idea to Exploring,
  # and an implement request moves its change to Implementing.
  def taken_by!(agent)
    update!(state: "taken", taken_by: agent, taken_at: Time.current)
    if change.agent_on?
      change.update!(agent_session_id: SecureRandom.uuid) if change.agent_session_id.nil?
    else
      change.update!(agent:, agent_taken_at: Time.current, agent_session_id: SecureRandom.uuid)
    end
    if kind == "explore" && change.phase == "idea"
      change.move_to!("exploring", by: agent)
    elsif kind == "implement"
      change.move_to!("implementing", by: agent)
    end
    self
  end

  # A new comment on the change as by's, its errors copied to the request's
  # comment.
  def new_comment(body, by:)
    Comment.new(change:, author: by, body: body.to_s).tap do |posted|
      posted.validate
      posted.errors.each { |error| errors.add(:comment, error.message) if error.attribute == :body }
    end
  end

  # Ends a request with state, as by.
  def close!(state, by:)
    update!(state:, finished_by: by, finished_at: Time.current)
  end
end
