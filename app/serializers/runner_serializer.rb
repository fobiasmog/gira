# JSON for a runner, for its owner (spec agent-runners, "List, rotate and
# revoke runners"): never its secret, only its last four characters, and the
# agents it holds a live lease of now. The secret is added to the response
# that creates or rotates it alone.
class RunnerSerializer
  # The agents that runners hold live leases of, by runner id, in a fixed
  # number of queries.
  def self.agents_for(runners)
    AgentLease.live.where(runner_id: runners.map(&:id)).includes(agent: :agent).order(:created_at, :id)
      .group_by(&:runner_id).transform_values { |leases| leases.map { |lease| { id: lease.agent_id, name: lease.agent.name, since: lease.created_at } } }
  end

  def initialize(runner, agents: nil)
    @runner = runner
    @agents = agents
  end

  def as_json(*)
    { id: @runner.id, name: @runner.name, last_characters: @runner.last_characters, created_at: @runner.created_at,
      last_contact_at: @runner.last_contact_at, agents: @agents || self.class.agents_for([ @runner ]).fetch(@runner.id, []) }
  end

  # For the response that creates or rotates the secret: the only time it is
  # shown, with the Goalner address that `bin/goalner-worker register` takes.
  def with_secret(goalner_url:)
    as_json.merge(secret: @runner.secret, goalner_url:)
  end
end
