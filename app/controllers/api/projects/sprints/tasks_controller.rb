# One sprint's root, non-archived tasks, done ones included, in column order
# (spec sprints, "Sprint task list"). Each card also names the sprint holding
# the task's most recent carried-over copy (carried_to), or null.
class Api::Projects::Sprints::TasksController < Api::BaseController
  include ProjectScoped

  def index
    sprint = @project.sprints.find(params[:sprint_id])
    tasks = sprint.tasks.kept.roots.in_column_order.includes(:project).to_a
    carried_to = carried_to_for(tasks.map(&:id))

    render json: TaskSerializer.cards(tasks).map { |card| card.merge(carried_to: carried_to[card[:id]]) }
  end

  private
    # The sprint of each task's newest copy, in one query for all of them.
    def carried_to_for(task_ids)
      copies = Task.where(origin_task_id: task_ids).left_joins(:sprint)
        .select("DISTINCT ON (tasks.origin_task_id) tasks.origin_task_id, sprints.id AS copy_sprint_id, sprints.title AS copy_sprint_title")
        .order("tasks.origin_task_id", id: :desc)

      copies.to_h do |copy|
        [ copy.origin_task_id, copy.copy_sprint_id && { id: copy.copy_sprint_id, title: copy.copy_sprint_title } ]
      end
    end
end
