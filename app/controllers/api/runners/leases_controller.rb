# Leases of agents to the calling runner (spec agent-runners, "Lease an
# agent", "One lease per agent" and "Renewing and ending a lease";
# add-runners-and-workspaces design.md, decision 2).
#
# - create: leases an agent the runner's owner can see, by the id of its
#   account; 404 for any other, deleted or not. 409 agent_leased or
#   workspace_elsewhere when another runner holds it or its change.
# - destroy: releases a lease of the runner; one that has ended already is
#   released again, changing nothing.
class Api::Runners::LeasesController < Api::Runners::BaseController
  LEASES_PER_HOUR = 60

  rate_limit to: LEASES_PER_HOUR, within: 1.hour, only: :create, scope: "runner_leases",
    by: -> { Current.runner.id }, with: -> { render_rate_limited }

  rescue_from AgentLease::Refused do |refusal|
    render_error :conflict, refusal.code, details: refusal.details
  end

  def create
    agent = Agent.kept.visible_to(Current.runner.user).includes(:user).find_by!(user_id: params[:agent_id])
    lease = AgentLease.lease!(agent:, runner: Current.runner)
    render json: AgentLeaseSerializer.new(lease, agent:, projects: reachable_projects(agent.user).order(:id).to_a), status: :created
  end

  def destroy
    Current.runner.leases.find(params[:id]).end!
    head :no_content
  end
end
