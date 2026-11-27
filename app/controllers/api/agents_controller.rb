# The agents the signed-in user can see: those they share a non-archived
# project with (spec agents, "Who can see and handle an agent"). Not opened
# to tokens, so neither a person's token nor an agent can handle agents.
class Api::AgentsController < Api::BaseController
  include AgentScoped
  skip_before_action :set_agent, only: :index

  # The active ones, each with the projects the user shares with it: what the
  # user chooses from when adding an agent to another project.
  def index
    agents = Agent.kept.visible_to(Current.user).joins(:user).order("users.name", :id)
      .includes(created_by: :agent, user: { avatar_attachment: :blob })
    shared = Membership.where(user_id: agents.map(&:user_id), project: Current.projects).includes(:project).group_by(&:user_id)

    render json: agents.map { |agent|
      projects = shared.fetch(agent.user_id, []).map(&:project).sort_by(&:title)
      AgentSerializer.new(agent, projects: projects.map { |project| project.slice(:id, :title, :short_name) })
    }
  end

  # Its name, model and instructions, any of them (spec agents, "Agent
  # settings"); null or empty clears a setting.
  def update
    Agent.transaction do
      @agent.user.update!(name: params[:name]) if params.key?(:name)
      @agent.update!(params.permit(:model, :instructions))
    end
    render json: AgentSerializer.new(@agent)
  end

  # Deletes the agent, in every project it belongs to. It can be restored.
  def destroy
    @agent.delete!
    head :no_content
  end
end
