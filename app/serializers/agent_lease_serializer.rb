# JSON for a lease just made (spec agent-runners, "Lease an agent"): the
# lease and its run token's value, shown here only; the agent and its
# settings; the projects the run token reaches; and the open change the
# agent is on in one of them, with what the worker needs to continue it: its
# base branch, the session of the agent's stint, its workspace and the
# request the agent took and has not finished. With it, where the run's MCP
# client connects (MCP_RESOURCE_URL), which the worker cannot tell from
# Goalner's address.
class AgentLeaseSerializer
  # projects: those the run token reaches.
  def initialize(lease, agent:, projects:)
    @lease = lease
    @agent = agent
    @projects = projects
  end

  def as_json(*)
    { lease: { id: @lease.id, started_at: @lease.created_at, run_token: @lease.run_token_value },
      agent: { id: @agent.user_id, name: @agent.name, model: @agent.model, instructions: @agent.instructions },
      projects: @projects.map { |project| { id: project.id, short_name: project.short_name } },
      mcp_url: Oauth.resource,
      change: }
  end

  private
    def change
      change = Change.kept.on_by(@agent.user).where(project_id: @projects.map(&:id)).includes(:project, workspace: :runner).first
      return unless change

      phase = change.phase_reported
      request = change.requests.taken.find_by(taken_by_id: @agent.user_id)
      { project: { id: change.project.id, short_name: change.project.short_name }, id: change.id, name: change.name, phase:,
        base_branch: change.base_branch, session_id: change.agent_session_id,
        workspace: (WorkspaceSerializer.new(change.workspace) if change.workspace),
        request: (ChangeRequestSerializer.new(request, change:, phase:).as_json if request) }
    end
end
