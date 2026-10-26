class Api::Projects::Milestones::RecoveriesController < Api::BaseController
  include ProjectScoped
  allow_token_access only: :create

  def create
    milestone = @project.milestones.deleted.find(params[:milestone_id])
    milestone.recover!
    render json: milestone.slice(:id, :title, :deleted_at).merge(milestone.progress)
  end
end
