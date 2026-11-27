# Runners, for their owner (spec agent-runners, "Runners" and "List, rotate
# and revoke runners"; add-runners-and-workspaces design.md, decision 1). Not
# opened to tokens: only a signed-in session handles runners. Another
# person's runner, and a revoked one, are a 404.
#
# Creating asks for the current password again, and shares its hourly limit
# with rotating a secret. The secret is returned here and never again.
class Api::Me::RunnersController < Api::BaseController
  include PasswordReentry
  rate_limit_per_user to: 10, within: 1.hour, only: :create, scope: "runners"
  before_action :require_reentered_password, only: :create

  # With the agents each one runs now.
  def index
    runners = Current.user.runners.active.order(created_at: :desc, id: :desc).to_a
    agents = RunnerSerializer.agents_for(runners)
    render json: runners.map { |runner| RunnerSerializer.new(runner, agents: agents.fetch(runner.id, [])) }
  end

  def create
    runner = Runner.issue(user: Current.user, name: params[:name].to_s)

    if runner.save
      render json: RunnerSerializer.new(runner, agents: []).with_secret(goalner_url: request.base_url), status: :created
    else
      render_validation_errors runner
    end
  end

  # Ends the runner and its leases for good.
  def destroy
    Current.user.runners.active.find(params[:id]).revoke!
    head :no_content
  end
end
