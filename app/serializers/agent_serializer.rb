# JSON for an agent, for the people who handle it (spec agents): its user
# card, who created it and when, and whether it is deleted. Its id is the id
# of its account, as in member lists and wherever a task or comment names it.
#
# - token_count: its live tokens, where the caller counted them.
# - removable: whether it can be removed from the project being listed, which
#   it cannot be from its only non-archived one.
# - lease: where it runs now, where the caller loaded it (spec agent-runners,
#   "Leases in the agent list").
#
# Its settings, model and instructions, are always included (spec agents,
# "Agent settings").
class AgentSerializer
  # Where each agent runs: its live lease's runner, the runner's owner and
  # since when, by the agent's user id, in a fixed number of queries.
  def self.leases_for(agents)
    AgentLease.live.where(agent_id: agents.map(&:user_id)).includes(runner: { user: [ :agent, { avatar_attachment: :blob } ] }).to_h do |lease|
      [ lease.agent_id, { runner: { name: lease.runner.name }, owner: UserSerializer.new(lease.runner.user).card, since: lease.created_at } ]
    end
  end

  def initialize(agent, **extras)
    @agent = agent
    @extras = extras
  end

  def as_json(*)
    UserSerializer.new(@agent.user).card.merge(
      created_by: UserSerializer.new(@agent.created_by).card,
      created_at: @agent.created_at,
      deleted_at: @agent.deleted_at,
      model: @agent.model,
      instructions: @agent.instructions,
      **@extras
    )
  end
end
