# JSON for tasks: a compact card for lists and boards, and the full detail.
class TaskSerializer
  Counts = Data.define(:subtasks, :subtasks_done, :comments)

  # Subtask and comment counts for many tasks in three queries.
  def self.counts_for(task_ids)
    subtasks = Task.kept.where(parent_id: task_ids).group(:parent_id).count
    done = Task.kept.where(parent_id: task_ids).joins(:status).where(statuses: { done: true }).group(:parent_id).count
    comments = Comment.kept.where(task_id: task_ids).group(:task_id).count

    task_ids.index_with { |id| Counts.new(subtasks: subtasks[id] || 0, subtasks_done: done[id] || 0, comments: comments[id] || 0) }
  end

  # Projects and changes preloaded, so a list costs the same few queries
  # however long it is.
  def self.cards(tasks)
    tasks = tasks.to_a
    ActiveRecord::Associations::Preloader.new(records: tasks, associations: %i[project change]).call
    counts = counts_for(tasks.map(&:id))
    tasks.map { |task| new(task, counts: counts[task.id]).card }
  end

  def initialize(task, counts: nil)
    @task = task
    @counts = counts || self.class.counts_for([ task.id ])[task.id]
  end

  def card
    {
      id: @task.id,
      number: @task.number,
      key: @task.key,
      title: @task.title,
      status_id: @task.status_id,
      position: @task.position,
      parent_id: @task.parent_id,
      change_id: @task.change_id,
      change: @task.change&.slice(:id, :name),
      in_tasks_md: @task.in_tasks_md,
      label_id: @task.label_id,
      assignee_id: @task.assignee_id,
      deadline: @task.deadline,
      important: @task.important,
      completed_at: @task.completed_at,
      archived_at: @task.archived_at,
      subtask_count: @counts.subtasks,
      subtask_done_count: @counts.subtasks_done,
      comment_count: @counts.comments
    }
  end

  def detail
    card.merge(
      description: @task.description,
      created_at: @task.created_at,
      creator: user(@task.creator),
      assignee: user(@task.assignee),
      status: @task.status&.slice(:id, :title, :done),
      label: @task.label&.slice(:id, :title),
      subtasks: @task.subtasks.includes(:status).map { |subtask| subtask_json(subtask) }
    )
  end

  private
    def user(user)
      UserSerializer.new(user).card if user
    end

    def subtask_json(subtask)
      { id: subtask.id, number: subtask.number, key: subtask.key, title: subtask.title, complete: subtask.done? }
    end
end
