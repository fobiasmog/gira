# The agents the calling runner can lease (spec agent-runners, "Agents a
# runner can run"): those its owner can see that are not deleted, by name,
# each with the projects it shares with the owner and its live lease.
# bin/goalner-worker lists them, and finds an agent by its name in them.
class Api::Runners::AgentsController < Api::Runners::BaseController
  def index
    owner = Current.runner.user
    agents = Agent.kept.visible_to(owner).joins(:user).includes(:user).order("users.name", :id).to_a
    owner_projects = owner.projects.kept.select(:id)
    projects = Membership.where(user_id: agents.map(&:user_id), project_id: owner_projects).joins(:project)
      .order("projects.short_name").pluck(:user_id, "projects.short_name").group_by(&:first)
    leases = AgentLease.live.where(agent_id: agents.map(&:user_id)).includes(:runner).index_by(&:agent_id)

    render json: agents.map { |agent|
      lease = leases[agent.user_id]
      { id: agent.user_id, name: agent.name, projects: projects.fetch(agent.user_id, []).map(&:last),
        lease: lease && { runner: { name: lease.runner.name }, this_runner: lease.runner_id == Current.runner.id, since: lease.created_at } }
    }
  end
end
