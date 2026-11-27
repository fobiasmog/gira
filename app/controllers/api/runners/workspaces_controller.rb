# Workspaces of changes, as the calling runner keeps them (spec
# agent-workspaces; add-runners-and-workspaces design.md, decisions 3 and 4).
#
# - record: the workspace of an open change whose agent the runner holds a
#   live lease of, in a project that lease's run token reaches; 404 for any
#   other change. The same path and branch again change nothing.
# - update: a checkpoint (head_commit, uncommitted), or a state (removed,
#   kept) once the change is archived. Another runner's workspace is a 404.
# - index: with ?to_remove=true, the runner's active or kept workspaces of
#   archived changes.
class Api::Runners::WorkspacesController < Api::Runners::BaseController
  def record
    change = Change.kept.find(params[:change_id])
    lease = Current.runner.leases.live.find_by!(agent_id: change.agent_id) if change.agent_on?
    raise ActiveRecord::RecordNotFound unless lease && reachable_projects(lease.agent).exists?(change.project_id)

    workspace = Workspace.record!(change:, runner: Current.runner, path: text_param(:path), branch: text_param(:branch))
    render json: WorkspaceSerializer.new(workspace)
  end

  def update
    workspace = Current.runner.workspaces.find(params[:id])
    if params.key?(:state)
      workspace.mark!(params[:state].to_s)
    else
      workspace.checkpoint!(head_commit: text_param(:head_commit), uncommitted: boolean_param(:uncommitted))
    end
    render json: WorkspaceSerializer.new(workspace)
  end

  def index
    raise ActionController::ParameterMissing, :to_remove unless params[:to_remove] == "true"

    workspaces = Current.runner.workspaces.to_remove.includes(:runner, change: :project).order(:id)
    render json: workspaces.map { |workspace| WorkspaceSerializer.new(workspace).with_change }
  end

  private
    def text_param(name)
      value = params.require(name)
      raise ActionController::ParameterMissing, name unless value.is_a?(String)

      value
    end

    # true or false, as JSON gives them; anything else is missing.
    def boolean_param(name)
      value = params[name]
      raise ActionController::ParameterMissing, name unless [ true, false ].include?(value)

      value
    end
end
