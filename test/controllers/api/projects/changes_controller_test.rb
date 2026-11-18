require "test_helper"

# Spec changes: "Changes in a project", "Create a change", "Change lists and
# statistics", "Open a change", "Archive a change", "Change task list", "Idea
# of a change", "Phase of a change", "Change history" and "Waiting for
# people"; spec openspec-changes, "Read a change".
class Api::Projects::ChangesControllerTest < ActionDispatch::IntegrationTest
  TEXT = "## 1. Model\n\n- [ ] 1.1 Add the table\n- [ ] 1.2 Add the model\n\n## 2. API\n\n- [ ] 2.1 Add the routes\n"

  setup do
    @project = projects(:goal)
    sign_in_as users(:one)
  end

  def create_change(name, project: @project) = project.project_changes.create!(name:)

  def create_task(title, change:, status: statuses(:goal_todo), **attributes)
    @project.tasks.create!(title:, change:, status:, creator: users(:one), **attributes)
  end

  def import(name, text = TEXT)
    Change::Import.new(project: @project, user: users(:two), name:, artifacts: { "tasks" => text }).run!.change
  end

  def names = response.parsed_body.map { |change| change["name"] }

  # Create a change

  test "create: 201 with an open change in Idea and no tasks" do
    post api_project_changes_path(@project), params: { name: "export-csv" }, as: :json

    assert_response :created
    assert_equal [ "export-csv", nil, "idea", false, { "by_status" => {}, "total" => 0 } ],
      response.parsed_body.values_at("name", "archived_at", "phase", "waiting_for_people", "task_counts")
    assert_equal [ "export-csv" ], @project.project_changes.kept.pluck(:name)
    assert_nil @project.project_changes.sole.idea
  end

  test "create with an idea: the change is in Idea with the idea as written, which only opening it returns" do
    idea = "People want a project's tasks as CSV for weekly reports."

    post api_project_changes_path(@project), params: { name: "export-csv", idea: }, as: :json

    assert_response :created
    assert_not response.parsed_body.key?("idea")
    get api_project_change_path(@project, "export-csv")
    assert_equal [ "idea", idea ], response.parsed_body.values_at("phase", "idea")
  end

  test "idea too long, or not a text: 422 on the idea, nothing created" do
    assert_no_difference -> { Change.count } do
      [ "a" * 100_001, { text: "x" }, [ "x" ] ].each do |idea|
        post api_project_changes_path(@project), params: { name: "export-csv", idea: }, as: :json
        assert_response :unprocessable_content
        assert response.parsed_body.dig("error", "fields", "idea").present?, idea.inspect[0, 20]
      end
    end
  end

  test "an invalid name, a missing name or the name of an open change: 422 on the name, nothing created" do
    create_change("add-labels")

    assert_no_difference -> { Change.count } do
      [ { name: "Export CSV" }, {}, { name: "add-labels" } ].each do |params|
        post api_project_changes_path(@project), params:, as: :json
        assert_response :unprocessable_content
        assert response.parsed_body.dig("error", "fields", "name").present?, params.inspect
      end
    end
  end

  test "the name of an archived change: a new change with no tasks, and the archived one keeps its tasks" do
    archived = create_change("add-labels")
    create_task("Model", change: archived)
    archived.archive!

    post api_project_changes_path(@project), params: { name: "add-labels" }, as: :json

    assert_response :created
    assert_not_equal archived.id, response.parsed_body["id"]
    assert_equal 0, response.parsed_body.dig("task_counts", "total")
    assert_equal 1, archived.tasks.count
  end

  test "the same name in two projects" do
    create_change("add-agents")
    sign_in_as users(:two)

    post api_project_changes_path(projects(:side)), params: { name: "add-agents" }, as: :json

    assert_response :created
    assert_equal [ "add-agents" ], @project.project_changes.pluck(:name)
  end

  test "an archived project or a project of others: 404 and nothing created" do
    post api_project_changes_path(projects(:side)), params: { name: "export-csv" }, as: :json
    assert_response :not_found

    @project.archive!
    post api_project_changes_path(@project), params: { name: "export-csv" }, as: :json
    assert_response :not_found
    assert_equal 0, Change.count
  end

  # Change lists and statistics

  test "open changes newest first with root task counts; none of them is active" do
    labels = create_change("add-labels")
    travel 1.minute
    create_change("export-csv")
    cards = [ create_task("A", change: labels), create_task("B", change: labels), create_task("C", change: labels, status: statuses(:goal_done)) ]
    9.times { |i| @project.tasks.create!(title: "Step #{i}", creator: users(:one), parent: cards[i % 3]) }

    get api_project_changes_path(@project)

    assert_response :success
    assert_equal %w[export-csv add-labels], names
    assert_equal({ "by_status" => { statuses(:goal_todo).id.to_s => 2, statuses(:goal_done).id.to_s => 1 }, "total" => 3 },
      response.parsed_body.last["task_counts"])
    assert response.parsed_body.none? { |change| change.key?("active") }
  end

  test "archived changes, most recently archived first, with their archive time, and not among the open ones" do
    labels = create_change("add-labels")
    login = create_change("fix-login")
    travel_to(1.day.ago) { labels.archive! }
    login.archive!

    get api_project_changes_path(@project, view: "archived")
    assert_equal %w[fix-login add-labels], names
    assert response.parsed_body.all? { |change| change["archived_at"].present? }

    get api_project_changes_path(@project)
    assert_empty response.parsed_body
  end

  test "an unknown view is 404" do
    get api_project_changes_path(@project, view: "available")

    assert_response :not_found
  end

  # Open a change; read a change

  test "open by name or id: the change, its counts and cards with their subtask counts, and its import" do
    change = import("add-labels")
    table = change.tasks.find_by!(title: "1.1 Add the table")
    table.update!(status: statuses(:goal_done))

    [ "add-labels", change.id ].each do |ref|
      get api_project_change_path(@project, ref)

      assert_response :success
      body = response.parsed_body
      assert_equal [ change.id, "add-labels", nil, 2 ], [ *body.values_at("id", "name", "archived_at"), body.dig("task_counts", "total") ]
      assert_equal [ [ "add-labels: 1. Model", 2, 1 ], [ "add-labels: 2. API", 1, 0 ] ],
        body["cards"].map { |card| card.values_at("title", "subtask_count", "subtask_done_count") }
      assert_equal users(:two).id, body.dig("imported_by", "id")
      assert body["imported_at"].present?
      assert_includes body["tasks_text"], "- [x] 1.1 Add the table <!-- goalner:#{table.key} -->"
    end
  end

  test "a change never imported has no importer, import time or text" do
    change = create_change("export-csv")

    get api_project_change_path(@project, "export-csv")

    assert_response :success
    assert_equal [ change.id, nil, nil, nil, [] ], response.parsed_body.values_at("id", "imported_by", "imported_at", "tasks_text", "cards")
  end

  test "an unknown change, a change of another project and an archived change by name: 404" do
    archived = create_change("add-labels").tap(&:archive!)
    foreign = create_change("theirs", project: projects(:side))

    [ "no-such-change", foreign.id, "theirs", "add-labels" ].each do |ref|
      get api_project_change_path(@project, ref)
      assert_response :not_found
    end

    get api_project_change_path(@project, archived.id)
    assert_response :success
    assert response.parsed_body["archived_at"].present?
  end

  # Archive a change

  test "archive with unfinished cards: archived, its cards stay with it and leave every board" do
    change = create_change("add-labels")
    cards = [ create_task("Done", change:, status: statuses(:goal_done)) ] + 3.times.map { |i| create_task("Open #{i}", change:) }

    post api_project_change_archival_path(@project, "add-labels")

    assert_response :success
    assert response.parsed_body["archived_at"].present?
    assert cards.all? { |card| card.reload.change == change }
    get api_project_changes_path(@project, view: "archived")
    assert_equal [ "add-labels" ], names
    get api_project_board_path(@project)
    assert_empty response.parsed_body["tasks"]
    get api_project_board_path(@project, change_id: change.id)
    assert_response :not_found
  end

  test "archive twice: succeeds, and the archive time is still yesterday's" do
    change = create_change("add-labels")
    travel_to(1.day.ago) { change.archive! }
    yesterday = change.reload.archived_at

    post api_project_change_archival_path(@project, change.id)

    assert_response :success
    assert_equal yesterday, change.reload.archived_at
    assert_equal yesterday.as_json, response.parsed_body["archived_at"]
  end

  test "archiving a change of another project: 404, and it stays open" do
    foreign = create_change("theirs", project: projects(:side))

    post api_project_change_archival_path(@project, foreign.id)

    assert_response :not_found
    assert_not foreign.reload.archived?
  end

  # Change task list

  test "tasks of a change: root, non-archived, in column order then position, done ones included" do
    change = create_change("export-csv")
    done = create_task("Done", change:, status: statuses(:goal_done))
    todo = 2.times.map { |i| create_task("To Do #{i}", change:) }
    @project.tasks.create!(title: "Step", creator: users(:one), parent: todo.first)
    create_task("Gone", change:).archive!
    create_task("Elsewhere", change: nil)

    get api_project_change_tasks_path(@project, "export-csv")

    assert_response :success
    assert_equal [ *todo.map(&:id), done.id ], response.parsed_body.map { |card| card["id"] }
    assert_equal statuses(:goal_done).id, response.parsed_body.last["status_id"]
  end

  test "tasks of an archived change are listed by its id" do
    change = create_change("add-labels")
    task = create_task("Model", change:)
    change.archive!

    get api_project_change_tasks_path(@project, change.id)

    assert_equal [ task.id ], response.parsed_body.map { |card| card["id"] }
  end

  test "tasks of a change of another project: 404 and no tasks" do
    foreign = create_change("theirs", project: projects(:side))
    projects(:side).tasks.create!(title: "Secret", creator: users(:two), change: foreign)

    get api_project_change_tasks_path(@project, foreign.id)

    assert_response :not_found
    assert_not_includes response.body, "Secret"
  end

  # Update a change: idea and phase

  def update_change(ref, headers: {}, **body)
    patch api_project_change_path(@project, ref), params: body, headers:, as: :json
  end

  def history = response.parsed_body["history"].map { |event| [ event["kind"], event.dig("actor", "name"), event["phase"] ] }

  test "edit before exploring: the idea is changed and cleared, and the change comes back as opened" do
    create_change("export-csv")

    update_change("export-csv", idea: "New idea")
    assert_response :success
    assert_equal [ "export-csv", "New idea", "idea", [], [], [] ], response.parsed_body.values_at("name", "idea", "phase", "history", "files", "cards")

    get api_project_change_path(@project, "export-csv")
    assert_equal "New idea", response.parsed_body["idea"]

    update_change("export-csv", idea: nil)
    assert_response :success
    assert_nil @project.project_changes.find_by!(name: "export-csv").idea
  end

  test "fixed once exploring starts: 422 on the idea, the idea unchanged" do
    @project.project_changes.create!(name: "export-csv", idea: "First")
    fish = create_agent(@project)
    update_change("export-csv", phase: "exploring", headers: bearer(issue_agent_token(fish, issuer: users(:one))))
    assert_response :success

    update_change("export-csv", idea: "Second")

    assert_response :unprocessable_content
    assert response.parsed_body.dig("error", "fields", "idea").present?
    assert_equal "First", @project.project_changes.find_by!(name: "export-csv").idea
  end

  test "agent moves the phase: the change is in Exploring, with the agent in its history" do
    create_change("export-csv")
    fish = create_agent(@project)

    update_change("export-csv", phase: "exploring", headers: bearer(issue_agent_token(fish, issuer: users(:one))))

    assert_response :success
    assert_equal "exploring", response.parsed_body["phase"]
    assert_equal [ [ "phase", "Fish", "exploring" ] ], history
    assert response.parsed_body["history"].first.dig("actor", "agent")
    assert response.parsed_body["history"].first["created_at"].present?
  end

  test "the idea and the phase in one request: the idea is taken as exploring starts" do
    create_change("export-csv")

    update_change("export-csv", idea: "Last word", phase: "exploring")

    assert_response :success
    assert_equal [ "Last word", "exploring" ], response.parsed_body.values_at("idea", "phase")
  end

  test "back to an earlier phase, and the same phase records nothing" do
    change = create_change("export-csv")
    change.update!(phase: "proposed")

    update_change(change.id, phase: "proposed")
    assert_equal [ "proposed", [] ], response.parsed_body.values_at("phase", "history")

    update_change(change.id, phase: "exploring")
    assert_response :success
    assert_equal [ [ "phase", "User One", "exploring" ] ], history
  end

  test "Done, an unknown phase or no phase cannot be chosen: 422 on the phase, unchanged" do
    change = create_change("export-csv")

    [ "done", "review", nil, 3 ].each do |phase|
      update_change("export-csv", phase:)
      assert_response :unprocessable_content
      assert response.parsed_body.dig("error", "fields", "phase").present?, phase.inspect
    end
    assert_equal [ "idea", 0 ], [ change.reload.phase, change.events.count ]
  end

  test "an archived change cannot be moved or edited: 422, phase unchanged" do
    change = create_change("fix-login").tap(&:archive!)

    update_change(change.id, phase: "exploring")
    assert_response :unprocessable_content
    assert response.parsed_body.dig("error", "fields", "base").present?
    update_change(change.id, idea: "Late")
    assert_response :unprocessable_content
    assert_equal [ "idea", nil, 0 ], [ change.reload.phase, change.idea, change.events.count ]

    update_change("fix-login", phase: "exploring")
    assert_response :not_found
  end

  test "a change of another project, or an archived project: 404" do
    foreign = create_change("theirs", project: projects(:side))

    update_change(foreign.id, phase: "exploring")
    assert_response :not_found
    assert_equal "idea", foreign.reload.phase
  end

  # Phase, waiting and history when listed and opened

  test "phase and waiting in the list: Exploring and waiting for Fish's answer" do
    export = create_change("export-csv")
    login = create_change("fix-login")
    fish = create_agent(@project).user
    export.move_to!("exploring", by: fish)
    export.comments.create!(author: fish, body: "Should archived tasks go into the file?")

    get api_project_changes_path(@project)

    listed = response.parsed_body.index_by { |change| change["name"] }
    assert_equal [ "exploring", true ], listed["export-csv"].values_at("phase", "waiting_for_people")
    assert_equal [ "idea", false ], listed["fix-login"].values_at("phase", "waiting_for_people")
    assert response.parsed_body.none? { |change| change.key?("idea") || change.key?("history") }

    login.comments.create!(author: fish, body: "?")
    login.archive!
    get api_project_changes_path(@project, view: "archived")
    assert_equal [ "fix-login", false ], response.parsed_body.first.values_at("name", "waiting_for_people")
  end

  test "idea, phase and history: opening a change returns them, and answering ends the wait" do
    @project.project_changes.create!(name: "export-csv", idea: "CSV for reports")
    fish = create_agent(@project).user
    change = @project.project_changes.find_by!(name: "export-csv")
    change.move_to!("exploring", by: fish)
    change.comments.create!(author: fish, body: "Archived tasks too?")

    get api_project_change_path(@project, "export-csv")
    assert_equal [ "CSV for reports", "exploring", true ], response.parsed_body.values_at("idea", "phase", "waiting_for_people")
    assert_equal [ [ "phase", "Fish", "exploring" ] ], history

    change.comments.create!(author: users(:one), body: "No.")
    get api_project_change_path(@project, "export-csv")
    assert_equal false, response.parsed_body["waiting_for_people"]
  end

  test "Done while every card of a change in Implementing is in the done column, and out of Done when one leaves it" do
    change = create_change("add-labels")
    cards = 4.times.map { |i| create_task("Card #{i}", change:, status: i.zero? ? statuses(:goal_work) : statuses(:goal_done)) }
    change.move_to!("implementing", by: users(:one))

    get api_project_change_path(@project, "add-labels")
    assert_equal "implementing", response.parsed_body["phase"]

    cards.first.update!(status: statuses(:goal_done))
    get api_project_change_path(@project, "add-labels")
    assert_equal "done", response.parsed_body["phase"]
    get api_project_changes_path(@project)
    assert_equal "done", response.parsed_body.first["phase"]
    get api_project_board_path(@project)
    assert_equal "done", response.parsed_body["changes"].first["phase"]

    cards.last.update!(status: statuses(:goal_todo))
    get api_project_changes_path(@project)
    assert_equal "implementing", response.parsed_body.first["phase"]
    assert_equal [ "implementing" ], change.events.map(&:phase)
  end

  test "files are listed with their paths and lengths, without their text" do
    Change::Import.new(project: @project, user: users(:one), name: "export-csv",
      artifacts: { "tasks" => TEXT, "proposal" => "# Proposal ✓", "specs" => { "export" => "## ADDED" } }).run!

    get api_project_change_path(@project, "export-csv")

    assert_equal [ { "path" => "proposal.md", "length" => 12 }, { "path" => "specs/export/spec.md", "length" => 8 } ], response.parsed_body["files"]
    assert_not_includes response.body, "# Proposal"
    assert_equal [ [ "import", "User One", nil ] ], history
    assert_equal %w[proposal.md specs/export/spec.md tasks.md], response.parsed_body["history"].first["paths"]
  end

  test "the changes list and the board take the same number of queries for one change and for five" do
    fish = create_agent(@project).user
    count_queries = lambda do |path|
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get path }
      queries
    end
    add_change = lambda do |name|
      change = create_change(name)
      create_task("Card", change:)
      change.comments.create!(author: fish, body: "?")
    end

    add_change.("change-0")
    one = [ count_queries.(api_project_changes_path(@project)), count_queries.(api_project_board_path(@project)) ]
    4.times { |i| add_change.("change-#{i + 1}") }
    five = [ count_queries.(api_project_changes_path(@project)), count_queries.(api_project_board_path(@project)) ]

    assert_equal one, five
    assert_equal 5, response.parsed_body["changes"].count { |change| change["waiting_for_people"] }
  end
end
