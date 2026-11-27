# JSON for the workspace of a change (spec agent-workspaces, "Workspace in
# change responses"): its runner's name, where it is, on which branch cut
# from which base branch, its state, and its latest checkpoint or null.
class WorkspaceSerializer
  # The workspaces of changes, with their runners, by change id, in one query.
  def self.for_changes(changes)
    Workspace.where(change_id: changes.map(&:id)).includes(:runner).index_by(&:change_id)
  end

  def initialize(workspace)
    @workspace = workspace
  end

  def as_json(*)
    { id: @workspace.id, runner: { name: @workspace.runner.name }, path: @workspace.path, branch: @workspace.branch,
      base_branch: @workspace.base_branch, state: @workspace.state, recorded_at: @workspace.created_at, checkpoint: }
  end

  # For a runner removing it: with its change and the change's project.
  def with_change
    change = @workspace.change
    as_json.merge(change: { id: change.id, name: change.name, project: { id: change.project.id, short_name: change.project.short_name } })
  end

  private
    def checkpoint
      return unless @workspace.checkpoint_at

      { head_commit: @workspace.head_commit, uncommitted: @workspace.uncommitted, at: @workspace.checkpoint_at }
    end
end
