# A user's open assigned work and upcoming deadlines (spec statistics). For a
# teammate, only projects both users belong to are included.
class Statistics
  DEADLINE_WINDOW = 7.days

  def initialize(subject:, viewer:)
    @subject = subject
    @project_ids = subject == viewer ? subject.projects.kept.ids : viewer.shared_project_ids_with(subject)
  end

  # Open root tasks grouped by project, then by column in column order
  # (backlog last).
  def overview
    tasks = open_tasks.includes(:status, :project).order(:number).to_a

    tasks.group_by(&:project).sort_by { |project, _| project.title }.map do |project, project_tasks|
      columns = project_tasks.group_by(&:status).sort_by { |status, _| status ? status.position : Float::INFINITY }
      {
        project: project.slice(:id, :title, :short_name),
        columns: columns.map do |status, column_tasks|
          { id: status&.id, title: status&.title, tasks: column_tasks.map { |task| task_json(task) } }
        end
      }
    end
  end

  # Open tasks due between now and seven days from now, soonest first.
  def deadlines
    open_tasks.where(deadline: Time.current..DEADLINE_WINDOW.from_now).includes(:project).order(:deadline)
      .map { |task| task_json(task).merge(deadline: task.deadline, project_id: task.project_id) }
  end

  private
    def open_tasks
      Task.kept.roots.not_done.where(project_id: @project_ids, assignee: @subject)
    end

    def task_json(task)
      { id: task.id, key: task.key, title: task.title, important: task.important }
    end
end
