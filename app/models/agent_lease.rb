# A lease of an agent to a runner (spec agent-runners, "Lease an agent", "One
# lease per agent" and "Renewing and ending a lease"; add-runners-and-
# workspaces design.md, decision 2). While it lives, its run token acts as
# the agent: an agent token issued by the runner's owner, which nobody sees
# but the worker and which ends with the lease.
#
# A lease lives while it has not ended and was renewed within the lease
# window (AGENT_LEASE_SECONDS, five minutes by default). Every take of a
# request with its run token renews it. A lapsed lease is ended lazily, by
# the next lease of its agent or the next request with its run token, so no
# job is needed. An agent has at most one lease that has not ended, which
# the partial unique index backs.
#
# agent_id is the agent's account, the user that changes and requests name.
class AgentLease < ApplicationRecord
  # A lease refused, with the error code and the details its response names.
  class Refused < StandardError
    attr_reader :code, :details

    def initialize(code, **details)
      @code = code
      @details = details
      super(code.to_s)
    end
  end

  belongs_to :agent, class_name: "User"
  belongs_to :runner
  has_one :run_token, class_name: "ApiToken", inverse_of: :agent_lease, dependent: nil

  scope :unended, -> { where(ended_at: nil) }
  scope :live, -> { unended.where(renewed_at: window.ago..) }

  # The value of the run token issued with the lease, readable once.
  attr_reader :run_token_value

  def self.window
    Rails.configuration.x.agents.lease_window
  end

  # Leases agent, an Agent its owner can see, to runner, and issues its run
  # token. A live lease of another runner, or the agent's change having its
  # workspace active on another runner, refuses it and changes nothing. The
  # same runner's lease, or a lapsed one, is ended and replaced. An agent on
  # a change without a session gets one (spec agent-workspaces, "Session of
  # a stint").
  def self.lease!(agent:, runner:)
    transaction do
      Agent.lock.find(agent.id) # One lease of an agent at a time.
      current = unended.find_by(agent_id: agent.user_id)
      if current&.live? && current.runner_id != runner.id
        raise Refused.new(:agent_leased, runner: current.runner.name, leased_at: current.created_at)
      end
      change = Change.kept.on_by(agent.user).first
      elsewhere = change&.workspace
      if elsewhere&.active? && elsewhere.runner_id != runner.id
        raise Refused.new(:workspace_elsewhere, runner: elsewhere.runner.name)
      end

      current&.end!
      create!(agent_id: agent.user_id, runner:, renewed_at: Time.current).tap do |lease|
        lease.issue_run_token!
        change&.give_session!
      end
    end
  end

  def live?
    ended_at.nil? && renewed_at > self.class.window.ago
  end

  def ended?
    ended_at.present?
  end

  # Whether it lives; one that lapsed is ended now.
  def live_or_end!
    return true if live?

    end!
    false
  end

  def renew!
    update_column(:renewed_at, Time.current)
  end

  # Ends the lease and deletes its run token, for good. The agent's change,
  # its requests and its workspace stay as they are.
  def end!
    transaction do
      update!(ended_at: Time.current) unless ended?
      ApiToken.where(agent_lease_id: id).delete_all
    end
  end

  def issue_run_token!
    token = ApiToken.issue_for_lease(self)
    token.save!
    @run_token_value = token.value
  end
end
