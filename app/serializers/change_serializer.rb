# JSON for changes (spec changes): a change with its phase, whether it is
# waiting for people and its task counts in lists, and with its idea,
# history, file paths, cards and last OpenSpec import when it is opened.
class ChangeSerializer
  # Task counts, done columns and waiting for all of them in three queries.
  def self.list(changes)
    changes = changes.to_a
    counts = Change.task_counts_for(changes)
    done_columns = Status.where(project_id: changes.map(&:project_id).uniq, done: true).pluck(:project_id, :id).to_h
    waiting = Change.waiting_for_people(changes)
    changes.map do |change|
      new(change, task_counts: counts.fetch(change.id), done_status_id: done_columns[change.project_id], waiting: waiting.include?(change.id)).as_json
    end
  end

  def initialize(change, task_counts: nil, done_status_id: nil, waiting: nil)
    @change = change
    @task_counts = task_counts || change.task_counts
    @done_status_id = done_status_id || change.project.done_status&.id
    @waiting = waiting.nil? ? change.waiting_for_people? : waiting
  end

  # phase is the reported one, Done included (add-change-conversation
  # design.md, decision 2).
  def as_json(*)
    { id: @change.id, name: @change.name, archived_at: @change.archived_at,
      phase: Change.reported_phase(@change.phase, @task_counts, @done_status_id),
      waiting_for_people: @waiting, task_counts: @task_counts }
  end

  # Opening a change, and the answer to an update or an import: its idea,
  # its history oldest first, the paths and lengths of its files but not
  # their text, its cards that are not archived, in column order, and the
  # marked tasks text, which is nil, as are its importer and import time,
  # until the first import.
  def detail
    as_json.merge(
      idea: @change.idea,
      imported_by: (UserSerializer.new(@change.imported_by).card if @change.imported_by),
      imported_at: @change.imported_at,
      tasks_text: @change.current_tasks_text,
      history: history,
      files: @change.files.in_order.pluck(:path, Arel.sql("char_length(change_files.text)")).map { |path, length| { path:, length: } },
      cards: TaskSerializer.cards(@change.tasks.kept.roots.in_column_order)
    )
  end

  private
    def history
      @change.events.includes(actor: [ :agent, { avatar_attachment: :blob } ]).map do |event|
        { kind: event.kind, actor: UserSerializer.new(event.actor).card, phase: event.phase, paths: event.paths, created_at: event.created_at }
      end
    end
end
