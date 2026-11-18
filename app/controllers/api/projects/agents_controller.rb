# A project's agents (spec agents, "Create an agent in a project" and "Delete
# an agent"): the list, active and deleted, and creation. Any member can do
# both. Not opened to tokens, so agents cannot create agents.
class Api::Projects::AgentsController < Api::BaseController
  include ProjectScoped
  include PasswordReentry
  # Shared with token issuing: creating an agent issues its first token.
  rate_limit_per_user to: 10, within: 1.hour, only: :create, scope: "agent_tokens"
  before_action :require_reentered_password, only: :create

  # With each agent's last check-in in the project, whether it is online,
  # and the open change it is on (spec change-requests, "Check-ins"). A
  # change in a project the member does not share is named by nothing.
  def index
    agents = Agent.of_project(@project).joins(:user).order("users.name", :id)
      .includes(created_by: :agent, user: { avatar_attachment: :blob }).to_a
    user_ids = agents.map(&:user_id)
    token_counts = ApiToken.of_agents.where(user_id: user_ids).group(:user_id).count
    elsewhere = Membership.where(user_id: user_ids).where.not(project_id: @project.id).joins(:project).merge(Project.kept).distinct.pluck(:user_id)
    check_ins = @project.memberships.where(user_id: user_ids).pluck(:user_id, :checked_in_at).to_h
    working_on = Change.kept.where(agent_id: user_ids).where.not(agent_taken_at: nil).index_by(&:agent_id)
    shared = Current.user.projects.kept.where(id: working_on.values.map(&:project_id)).pluck(:id)

    render json: agents.map { |agent|
      change = working_on[agent.user_id]
      AgentSerializer.new(agent, token_count: token_counts.fetch(agent.user_id, 0), removable: elsewhere.include?(agent.user_id),
        checked_in_at: check_ins[agent.user_id], online: Agent.online?(check_ins[agent.user_id]),
        working_on: change && (shared.include?(change.project_id) ? { id: change.id, name: change.name, project_id: change.project_id } : { id: nil, name: nil, project_id: nil }))
    }
  end

  # The agent joins the project at once, and its first token is issued with
  # it. The token's value is returned here and never again. A token that
  # cannot be issued creates no agent.
  def create
    agent = token = nil
    Agent.transaction do
      agent = Agent.create_in!(@project, name: params[:name].to_s, created_by: Current.user)
      token_params = params.fetch(:token, {}).permit(:name, :access, channels: [])
      token = ApiToken.issue_for_agent(agent, issuer: Current.user, channels: token_params[:channels], **token_params.slice(:name, :access))
      token.save!
    end

    render json: AgentSerializer.new(agent, token_count: 1, removable: false, checked_in_at: nil, online: false, working_on: nil).as_json
      .merge(first_token: AgentTokenSerializer.new(token).with_value),
      status: :created
  end

  private
    # The agent's own fields are named as they are, and its first token's
    # under "token.", so the two names cannot be confused.
    def render_record_invalid(exception)
      return super unless exception.record.is_a?(ApiToken)

      fields = exception.record.errors.to_hash(true).transform_keys { |attribute| "token.#{attribute}" }
      render_error :unprocessable_content, :validation_failed, fields: fields
    end
end
