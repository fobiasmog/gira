# Requests of a project's changes, as agents work them (spec change-requests,
# "Take a request", "Finish a request", "Cancel a request" and "Full
# context"; add-change-requests design.md, decisions 3, 6, 7 and 13).
#
# - claim: an agent takes the next request for it, or none; always 200, with
#   {request: null} for none, so that no client mistakes it for a taken one.
#   A taken request names its change's base branch, session and workspace.
#   With a run token, the take keeps to its lease's runner and renews the
#   lease (add-runners-and-workspaces design.md, decisions 2 and 3).
# - finish: the agent that took a request finishes it as done or failed.
# - cancellation: members cancel an open request.
# - context_full: an agent whose context is full blocks its change.
#
# Only agents claim and report a full context: people get 403 agents_only.
class Api::Projects::RequestsController < Api::BaseController
  include ProjectScoped
  allow_token_access only: %i[ claim finish cancellation context_full ]
  before_action :require_agent, only: %i[ claim context_full ]
  before_action :set_change_request, only: %i[ finish cancellation ]

  def claim
    lease = Current.api_token&.agent_lease
    taken = ChangeRequest.take!(project: @project, agent: Current.user, runner: lease&.runner)
    lease&.renew!
    render json: { request: (serialize(taken).taken if taken) }
  end

  def finish
    @change_request.finish!(by: Current.user, outcome: params[:outcome].to_s, comment: params[:comment])
    render json: serialize(@change_request)
  end

  def cancellation
    @change_request.cancel!(by: Current.user)
    render json: serialize(@change_request)
  end

  def context_full
    render json: { blocked: Change.block_for_full_context!(project: @project, agent: Current.user) }
  end

  private
    def require_agent
      render_error :forbidden, :agents_only unless Current.user.agent?
    end

    def set_change_request
      @change_request = ChangeRequest.in_project(@project).find(params[:id])
    end

    def serialize(change_request)
      change = change_request.change
      ChangeRequestSerializer.new(change_request, change:, phase: change.phase_reported)
    end
end
