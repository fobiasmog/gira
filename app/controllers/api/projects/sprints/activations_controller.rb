class Api::Projects::Sprints::ActivationsController < Api::BaseController
  include ProjectScoped

  def create
    sprint = @project.sprints.kept.find(params[:sprint_id])
    sprint.activate!
    render json: SprintSerializer.new(sprint)
  end
end
