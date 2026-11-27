# A project's agents (spec agents, "Create an agent in a project" and "Delete
# an agent"): the list, active and deleted, and creation. Any member can do
# both. Not opened to tokens, so agents cannot create agents.
class Api::Projects::AgentsController < Api::BaseController
  include ProjectScoped

  # With each agent's last check-in in the project, whether it is online,
  # and the open change it is on (spec change-requests, "Check-ins"), and
  # where it runs (spec agent-runners, "Leases in the agent list"). A
  # change in a project the member does not share is named by nothing.
  def index
    agents = Agent.of_project(@project).joins(:user).order("users.name", :id)
      .includes(created_by: :agent, user: { avatar_attachment: :blob }).to_a
    user_ids = agents.map(&:user_id)
    token_counts = ApiToken.issued_by_people.where(user_id: user_ids).group(:user_id).count
    elsewhere = Membership.where(user_id: user_ids).where.not(project_id: @project.id).joins(:project).merge(Project.kept).distinct.pluck(:user_id)
    check_ins = @project.memberships.where(user_id: user_ids).pluck(:user_id, :checked_in_at).to_h
    working_on = Change.kept.where(agent_id: user_ids).where.not(agent_taken_at: nil).index_by(&:agent_id)
    shared = Current.user.projects.kept.where(id: working_on.values.map(&:project_id)).pluck(:id)
    leases = AgentSerializer.leases_for(agents)

    render json: agents.map { |agent|
      change = working_on[agent.user_id]
      AgentSerializer.new(agent, token_count: token_counts.fetch(agent.user_id, 0), removable: elsewhere.include?(agent.user_id),
        checked_in_at: check_ins[agent.user_id], online: Agent.online?(check_ins[agent.user_id]),
        working_on: change && (shared.include?(change.project_id) ? { id: change.id, name: change.name, project_id: change.project_id } : { id: nil, name: nil, project_id: nil }),
        lease: leases[agent.user_id])
    }
  end

  # The agent joins the project at once, with its settings. It has no token:
  # a runner leases it, or a member issues one (Api::Agents::TokensController).
  def create
    agent = Agent.create_in!(@project, name: params[:name].to_s, created_by: Current.user, **settings_params)

    render json: AgentSerializer.new(agent, token_count: 0, removable: false, checked_in_at: nil, online: false, working_on: nil, lease: nil),
      status: :created
  end

  private
    def settings_params
      params.permit(:model, :instructions).to_h.symbolize_keys
    end
end
