# JSON for an agent, for the people who handle it (spec agents): its user
# card, who created it and when, and whether it is deleted. Its id is the id
# of its account, as in member lists and wherever a task or comment names it.
#
# - token_count: its live tokens, where the caller counted them.
# - removable: whether it can be removed from the project being listed, which
#   it cannot be from its only non-archived one.
class AgentSerializer
  def initialize(agent, **extras)
    @agent = agent
    @extras = extras
  end

  def as_json(*)
    UserSerializer.new(@agent.user).card.merge(
      created_by: UserSerializer.new(@agent.created_by).card,
      created_at: @agent.created_at,
      deleted_at: @agent.deleted_at,
      **@extras
    )
  end
end
