# Restores a deleted agent (spec agents, "Restore an agent"). Any member of
# a project it belongs to can; it comes back with no tokens and no tasks.
class Api::Agents::RestorationsController < Api::BaseController
  include AgentScoped

  def create
    @agent.restore!
    render json: AgentSerializer.new(@agent), status: :created
  end
end
