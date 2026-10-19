# Sprints (spec sprints).
class Api::Projects::SprintsController < Api::BaseController
  include ProjectScoped

  VIEWS = %w[all available archived].freeze

  # ?view=all (default, non-archived), available or archived; newest first.
  def index
    sprints = case params.fetch(:view, "all").presence_in(VIEWS)
    when "all" then @project.sprints.kept
    when "available" then @project.sprints.available
    when "archived" then @project.sprints.archived
    else raise ActiveRecord::RecordNotFound
    end

    render json: sprints.order(created_at: :desc, id: :desc).map { |sprint| SprintSerializer.new(sprint) }
  end

  # Optional flags: activate (make it the active sprint) and carry_over (copy
  # the unfinished tasks of the currently active sprint into it).
  def create
    sprint = nil
    @project.transaction do
      previous = @project.active_sprint
      sprint = @project.sprints.create!(params.permit(:title, :starts_on, :ends_on))
      previous&.carry_over_to(sprint) if flag?(:carry_over)
      sprint.activate! if flag?(:activate)
    end

    render json: SprintSerializer.new(sprint.reload), status: :created
  end

  private
    def flag?(name)
      ActiveModel::Type::Boolean.new.cast(params[name])
    end
end
