# Rotates a runner's secret (spec agent-runners, "List, rotate and revoke
# runners"; add-runners-and-workspaces design.md, decision 1): the old one
# stops at once, and so do the runner's leases; its name and workspaces
# stay. Asks for the current password again, and counts toward the hourly
# limit on creating runners. The new secret is returned here and never again.
class Api::Me::Runners::SecretRotationsController < Api::BaseController
  include PasswordReentry
  rate_limit_per_user to: 10, within: 1.hour, scope: "runners"
  before_action :set_runner, :require_reentered_password

  def create
    @runner.rotate_secret!
    render json: RunnerSerializer.new(@runner, agents: []).with_secret(goalner_url: request.base_url), status: :created
  end

  private
    def set_runner
      @runner = Current.user.runners.active.find(params[:runner_id])
    end
end
