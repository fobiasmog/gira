# Project members (spec project-membership, "Member list and removal"):
# people and agents, the agents marked as such. Deleted agents are neither
# listed nor removable.
class Api::Projects::MembersController < Api::BaseController
  include ProjectScoped
  allow_token_access only: :index
  rescue_from Agent::LastProject, with: :render_last_project

  def index
    render json: @project.listed_members.map { |member| UserSerializer.new(member).card }
  end

  # Only the owner removes a person; any member removes an agent, except
  # from the agent's only project (spec agents, "Agents in projects"). The
  # removed member's tasks in the project become unassigned.
  def destroy
    member = @project.members.active.find(params[:id])
    raise Forbidden if @project.owned_by?(member)
    require_owner! unless member.agent?

    @project.remove_member!(member)
    head :no_content
  end

  private
    def render_last_project
      message = ActiveModel::Error.new(Agent.new, :base, :last_project).full_message
      render_error :unprocessable_content, :validation_failed, fields: { base: [ message ] }
    end
end
