# A project's board: column management and task placement (spec
# project-board). Every operation runs in one transaction holding a lock on
# the project row, so concurrent moves cannot interleave and the done column
# is recomputed before anyone else sees the change.
class Board
  class Error < StandardError
    attr_reader :record

    def initialize(record)
      @record = record
      super("board change refused")
    end
  end

  KEEP_SPRINT = Object.new.freeze

  def initialize(project)
    @project = project
  end

  # A new column goes immediately before the done column.
  def add_column(title:)
    locked do
      status = @project.statuses.create!(title: title)
      done = @project.done_status
      status.insert_at(done.position) if done
      recompute_done_column
      status.reload
    end
  end

  def rename_column(status, title:)
    status.update!(title: title)
    status
  end

  def move_column(status, position:)
    locked do
      status.insert_at(clamp(position, @project.statuses.count))
      recompute_done_column
      status.reload
    end
  end

  # The column's tasks move, with all their data, to the end of the first
  # remaining column, each staying in its sprint; moving into the done column
  # completes them. The last remaining column cannot be deleted.
  def delete_column(status)
    locked do
      if @project.statuses.count == 1
        status.errors.add(:base, :last_column)
        raise Error, status
      end

      target = @project.statuses.where.not(id: status.id).first
      # One at a time and freshly loaded: each move renumbers the remaining ones.
      status.tasks.kept.order(:position, :id).ids.each { |id| Task.find(id).update!(status: target) }
      # Archived tasks are read-only and have no position; only their column changes.
      status.tasks.archived.update_all(status_id: target.id)
      status.destroy!
      recompute_done_column
    end
  end

  # Moves a root task to a position in a column (which is required), and into
  # another sprint or none when sprint_id is given. Positions stay contiguous
  # in both affected lists.
  def place(task, status_id:, position:, sprint_id: KEEP_SPRINT)
    locked do
      task.lock!
      if task.parent_id
        task.errors.add(:base, :subtask_placement)
        raise Error, task
      end

      task.status_id = status_id
      task.sprint_id = sprint_id unless sprint_id.equal?(KEEP_SPRINT)
      raise Error, task unless task.save

      siblings = Task.where(project_id: task.project_id, status_id: task.status_id, sprint_id: task.sprint_id, parent_id: nil).kept
      task.insert_at(clamp(position, siblings.count))
      task.reload
    end
  end

  private
    def locked(&)
      @project.with_lock(&)
    end

    def recompute_done_column
      statuses = @project.statuses.reload
      statuses.where(done: true).where.not(id: statuses.last.id).update_all(done: false)
      statuses.last.update!(done: true) unless statuses.last.done?
    end

    def clamp(position, count)
      position.to_i.clamp(0, [ count - 1, 0 ].max)
    end
end
