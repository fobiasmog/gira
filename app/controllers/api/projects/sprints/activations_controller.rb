class Api::Projects::Sprints::ActivationsController < Api::BaseController
  include ProjectScoped
  allow_token_access only: :create

  def create
    sprint = @project.sprints.kept.find(params[:sprint_id])
    sprint.activate!
    render json: SprintSerializer.new(sprint)
  end
end
