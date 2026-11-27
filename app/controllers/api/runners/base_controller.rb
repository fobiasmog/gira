# Base for the runner endpoints under /api/runner (spec agent-runners,
# "Runner authentication"; add-runners-and-workspaces design.md, decisions 1
# and 4). They authenticate by a runner secret alone, in the Authorization
# header's Bearer scheme: a session or an API token gets 401, like a missing
# secret. Runner secrets are known here only.
#
# No session and no CSRF token: an ActionController::API, which has neither
# cookies nor a session (spec security-baseline, "Cross-site request forgery
# protection"). Errors use the API's envelope (ApiErrors).
#
# A runner (Current.runner) is no user: lookups are scoped to its own leases
# and workspaces and the agents its owner can see. Each runner may make
# REQUESTS_PER_MINUTE requests a minute.
class Api::Runners::BaseController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods
  include ApiErrors

  REQUESTS_PER_MINUTE = 300

  before_action :require_runner
  rate_limit to: REQUESTS_PER_MINUTE, within: 1.minute, scope: "runner_requests",
    by: -> { Current.runner.id }, with: -> { render_rate_limited }

  private
    def require_runner
      runner = authenticate_with_http_token { |value| Runner.find_active_by_secret(value) }
      return render_error(:unauthorized, :invalid_runner_secret) unless runner

      Current.runner = runner
      runner.touch_contact!
    end

    # The owner's non-archived projects that agent_user belongs to: what a
    # run token of the agent, issued by the owner, reaches (spec agents,
    # "Agent token reach").
    def reachable_projects(agent_user)
      agent_user.projects.kept.where(id: Current.runner.user.projects.kept.select(:id))
    end
end
