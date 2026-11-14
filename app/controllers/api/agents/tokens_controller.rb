# An agent's tokens (spec agents, "Issue agent tokens" and "List and revoke
# agent tokens"). Everyone who can see the agent lists them and revokes any,
# whoever issued it. Issuing asks for the issuer's own password again. Not
# opened to tokens: an agent cannot issue tokens, for itself or for others.
class Api::Agents::TokensController < Api::BaseController
  include AgentScoped
  include PasswordReentry
  # Shared with agent creation, which issues a first token.
  rate_limit_per_user to: 10, within: 1.hour, only: :create, scope: "agent_tokens"
  before_action :require_reentered_password, only: :create

  def index
    tokens = @agent.tokens.includes(issuer: [ :agent, { avatar_attachment: :blob } ]).order(created_at: :desc, id: :desc)
    render json: tokens.map { |token| AgentTokenSerializer.new(token) }
  end

  # The value is returned here and never again.
  def create
    token = ApiToken.issue_for_agent(@agent, issuer: Current.user, channels: params[:channels], **params.permit(:name, :access))

    if token.save
      render json: AgentTokenSerializer.new(token).with_value, status: :created
    else
      render_validation_errors token
    end
  end

  def destroy
    @agent.tokens.find(params[:id]).destroy!
    head :no_content
  end
end
