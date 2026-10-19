# Archives a sprint, optionally carrying its unfinished tasks over to another
# sprint of the same project (carry_to_sprint_id).
class Api::Projects::Sprints::ArchivalsController < Api::BaseController
  include ProjectScoped

  def create
    sprint = @project.sprints.kept.find(params[:sprint_id])
    target = @project.sprints.kept.where.not(id: sprint.id).find(params[:carry_to_sprint_id]) if params[:carry_to_sprint_id].present?

    sprint.archive!(carry_to: target)
    render json: SprintSerializer.new(sprint)
  end
end
