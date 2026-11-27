# JSON for changes (spec changes): a change with its phase, whether it is
# waiting for people, its task counts, its open request and its agent in
# lists, and with its idea, history, file paths, cards and last OpenSpec
# import when it is opened (spec change-requests, "Open request and agent of
# a change"; add-change-requests design.md, decisions 4 and 6). Lists and
# the detail name its base branch and its workspace (spec agent-workspaces,
# "Workspace in change responses").
class ChangeSerializer
  # Task counts, done columns, waiting, open requests and the users these
  # and the agents name, for all of them in a fixed number of queries.
  def self.list(changes)
    changes = changes.to_a
    counts = Change.task_counts_for(changes)
    done_columns = Status.where(project_id: changes.map(&:project_id).uniq, done: true).pluck(:project_id, :id).to_h
    waiting = Change.waiting_for_people(changes)
    requests = ChangeRequest.unfinished.where(change_id: changes.map(&:id)).index_by(&:change_id)
    users = ChangeRequestSerializer.users_for(requests.values, extra_ids: changes.map(&:agent_id))
    workspaces = WorkspaceSerializer.for_changes(changes)
    changes.map do |change|
      new(change, task_counts: counts.fetch(change.id), done_status_id: done_columns[change.project_id], waiting: waiting.include?(change.id),
        request: requests[change.id], users:, workspace: workspaces[change.id]).as_json
    end
  end

  # request: the open request, or nil for none, where the caller loaded it;
  # users: the users it and the agent name, by id; workspace: the change's
  # workspace, or nil for none, where the caller loaded it.
  def initialize(change, task_counts: nil, done_status_id: nil, waiting: nil, request: :load, users: nil, workspace: :load)
    @change = change
    @task_counts = task_counts || change.task_counts
    @done_status_id = done_status_id || change.project.done_status&.id
    @waiting = waiting.nil? ? change.waiting_for_people? : waiting
    @request = request == :load ? change.requests.unfinished.first : request
    @users = users || ChangeRequestSerializer.users_for([ @request ].compact, extra_ids: [ change.agent_id ])
    @workspace = workspace == :load ? change.workspace : workspace
  end

  # phase is the reported one, Done included (add-change-conversation
  # design.md, decision 2).
  def as_json(*)
    phase = Change.reported_phase(@change.phase, @task_counts, @done_status_id)
    { id: @change.id, name: @change.name, archived_at: @change.archived_at,
      phase:, base_branch: @change.base_branch, waiting_for_people: @waiting, task_counts: @task_counts,
      request: (ChangeRequestSerializer.new(@request, change: @change, phase:, users: @users) if @request),
      agent: agent, workspace: (WorkspaceSerializer.new(@workspace) if @workspace) }
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
    # The user it names, picked or on the change, since when it is on it,
    # and since when it is blocked.
    def agent
      return unless @change.agent_id

      { user: UserSerializer.new(@users.fetch(@change.agent_id)).card, on: @change.agent_on?,
        since: @change.agent_taken_at, blocked_at: @change.agent_blocked_at }
    end

    # Phase moves, imports, releases and blocks, merged by time with up to
    # three entries for each request: asked, taken, and done, failed or
    # cancelled. At the same moment a request's entries come first, so a
    # take precedes the move it causes and a cancel the release.
    def history
      events = @change.events.includes(actor: [ :agent, { avatar_attachment: :blob } ], agent: [ :agent, { avatar_attachment: :blob } ]).map do |event|
        entry(event.kind, event.actor, event.created_at, phase: event.phase, paths: event.paths,
          agent: (UserSerializer.new(event.agent).card if event.agent))
      end
      requests = @change.requests.order(:id).to_a
      users = ChangeRequestSerializer.users_for(requests)
      steps = requests.flat_map do |request|
        [ [ "asked", request.requested_by_id, request.created_at ],
          ([ "taken", request.taken_by_id, request.taken_at ] if request.taken_at),
          ([ request.state, request.finished_by_id, request.finished_at ] if request.finished_at) ].compact.map do |state, user_id, time|
          entry("request", (users[user_id] if user_id), time, step: request.kind, state:)
        end
      end

      (steps.each_with_index.map { |step, index| [ step, 0, index ] } + events.each_with_index.map { |event, index| [ event, 1, index ] })
        .sort_by { |item, rank, index| [ item[:created_at], rank, index ] }.map(&:first)
    end

    def entry(kind, actor, created_at, phase: nil, paths: nil, agent: nil, step: nil, state: nil)
      { kind:, actor: (UserSerializer.new(actor).card if actor), phase:, paths:, agent:, step:, state:, created_at: }
    end
end
