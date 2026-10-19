# Milestones (spec milestones). Deleting keeps the tasks' reference so that
# recovering restores the grouping.
class Api::Projects::MilestonesController < Api::BaseController
  include ProjectScoped
  before_action :set_milestone, only: %i[ show destroy ]

  # ?view=deleted lists deleted milestones, for recovery.
  def index
    milestones = params[:view] == "deleted" ? @project.milestones.deleted : @project.milestones.kept
    render json: milestones.order(:created_at).map { |milestone| milestone_json(milestone) }
  end

  def show
    tasks = @milestone.tasks.kept.order(:number).includes(:project)
    render json: milestone_json(@milestone).merge(tasks: TaskSerializer.cards(tasks))
  end

  def create
    milestone = @project.milestones.create!(params.permit(:title))
    render json: milestone_json(milestone), status: :created
  end

  def destroy
    @milestone.delete!
    head :no_content
  end

  private
    def set_milestone
      @milestone = @project.milestones.kept.find(params[:id])
    end

    def milestone_json(milestone)
      milestone.slice(:id, :title, :deleted_at).merge(milestone.progress)
    end
end
