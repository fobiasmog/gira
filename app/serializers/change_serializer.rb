# JSON for changes (spec changes): a change with its task counts in lists,
# and with its cards and its last OpenSpec import when it is opened.
class ChangeSerializer
  # Task counts for all of them in one query.
  def self.list(changes)
    changes = changes.to_a
    counts = Change.task_counts_for(changes)
    changes.map { |change| new(change, task_counts: counts.fetch(change.id)).as_json }
  end

  def initialize(change, task_counts: nil)
    @change = change
    @task_counts = task_counts
  end

  def as_json(*)
    { id: @change.id, name: @change.name, archived_at: @change.archived_at, task_counts: @task_counts || @change.task_counts }
  end

  # Opening a change, and the answer to an import: its cards that are not
  # archived, in column order, and the marked tasks text, which is nil, as
  # are its importer and import time, until the first import.
  def detail
    as_json.merge(
      imported_by: (UserSerializer.new(@change.imported_by).card if @change.imported_by),
      imported_at: @change.imported_at,
      tasks_text: @change.current_tasks_text,
      cards: TaskSerializer.cards(@change.tasks.kept.roots.in_column_order)
    )
  end
end
