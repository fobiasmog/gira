# Every task has a column (change sprint-based-backlog). Tasks without one
# move to their project's first column, appended in their old order after the
# tasks already there in the same sprint and under the same parent. Archived
# tasks keep no position. A task that lands in a done column is completed now.
class RequireTaskColumn < ActiveRecord::Migration[8.1]
  def up
    change_column_null :tasks, :status_id, false
  end

  # Tasks stay in the column they were moved to.
  def down
    change_column_null :tasks, :status_id, true
  end
end
