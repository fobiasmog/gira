# The runner itself (spec agent-runners, "Runner authentication"): its name
# and its owner's, with which `bin/goalner-worker register` checks a secret.
class Api::Runners::ProfilesController < Api::Runners::BaseController
  def show
    render json: { id: Current.runner.id, name: Current.runner.name, owner: { name: Current.runner.user.name } }
  end
end
