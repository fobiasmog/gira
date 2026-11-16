# Adds an agent the user can see to another project they are a member of
# (spec agents, "Agents in projects"). It joins at once, without an
# invitation. A deleted agent, like one the user cannot see, is a 404.
class Api::Projects::AgentMembershipsController < Api::BaseController
  include ProjectScoped

  def create
    agent = Agent.kept.visible_to(Current.user).find_by!(user_id: params.require(:agent_id))
    @project.memberships.find_or_create_by!(user: agent.user)

    render json: AgentSerializer.new(agent), status: :created
  end
end
