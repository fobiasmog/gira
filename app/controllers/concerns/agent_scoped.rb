# Loads the agent of an agent-scoped API request through the projects the
# current user shares with it (spec agents, "Who can see and handle an
# agent"; add-agents design.md, decision 4). An unknown agent and one the
# user shares no non-archived project with are the same 404, deleted or not.
#
# The id is the id of the agent's account: the one that member lists,
# assignees and authors carry.
module AgentScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_agent
  end

  private
    def set_agent
      @agent = Agent.visible_to(Current.user).find_by!(user_id: params[:agent_id] || params[:id])
    end
end
