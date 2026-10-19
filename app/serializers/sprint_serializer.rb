class SprintSerializer
  def initialize(sprint)
    @sprint = sprint
  end

  def as_json(*)
    @sprint.slice(:id, :title, :starts_on, :ends_on, :active, :archived_at)
      .merge(task_counts: @sprint.task_counts)
  end
end
