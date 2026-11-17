require "test_helper"

# Agents in the tracker (spec agents, "Agents work like members"; spec tasks,
# "Tasks assigned to the requester" and "Edit task fields"; spec
# project-membership, "Teammates"; add-agents design.md, decisions 8 and 10).
# goal: one (owner, "Alice") and two ("Bob"). side: two (owner) and stranger.
class AgentsAtWorkTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @goal = projects(:goal)
    @fish = create_agent(@goal, name: "Fish")
    @owl = create_agent(@goal, name: "Owl")
    @fish_token = issue_agent_token(@fish, issuer: users(:two))
    @owl_token = issue_agent_token(@owl, issuer: users(:two))
  end

  def task(title, **attributes)
    @goal.tasks.create!(title: title, creator: users(:one), status: statuses(:goal_todo), **attributes)
  end

  def assigned(token_or_nil = nil, project: @goal)
    get api_project_tasks_path(project, view: "assigned"), headers: token_or_nil ? bearer(token_or_nil) : {}
    assert_response :success
    response.parsed_body
  end

  # Agents work like members

  test "person assigns to an agent" do
    target = task("Ship it")
    sign_in_as users(:two)

    patch api_project_task_path(@goal, target.id), params: { assignee_id: @fish.user.id }, as: :json

    assert_response :success
    assert_equal [ @fish.user.id, "Fish", true ], response.parsed_body["assignee"].values_at("id", "name", "agent")
  end

  test "agent delegates to another agent: it creates a task and a subtask assigned to the other" do
    parent = task("Ship it", assignee: @fish.user)

    post api_project_tasks_path(@goal), params: { title: "Research", assignee_id: @owl.user.id }, headers: bearer(@fish_token), as: :json

    assert_response :created
    assert_equal [ @fish.user.id, @owl.user.id ], [ response.parsed_body.dig("creator", "id"), response.parsed_body.dig("assignee", "id") ]

    post api_project_task_subtasks_path(@goal, parent.id), params: { title: "Write tests" }, headers: bearer(@fish_token), as: :json
    assert_response :created
    subtask = Task.find(response.parsed_body["id"])
    patch api_project_task_path(@goal, subtask.id), params: { assignee_id: @owl.user.id }, headers: bearer(@fish_token), as: :json

    assert_response :success
    assert_equal [ @fish.user, @owl.user, parent ], [ subtask.reload.creator, subtask.assignee, subtask.parent ]
  end

  test "attribution: a comment made with a token Bob issued is the agent's" do
    target = task("Ship it", assignee: @fish.user)

    post api_project_task_comments_path(@goal, target.id), params: { body: "On it" }, headers: bearer(@fish_token), as: :json

    assert_response :created
    assert_equal [ @fish.user.id, "Fish", true ], response.parsed_body["author"].values_at("id", "name", "agent")
    assert_equal @fish.user, target.comments.sole.author
  end

  test "an agent moves, completes and archives its task" do
    target = task("Ship it", assignee: @fish.user)

    patch api_project_task_placement_path(@goal, target.id), params: { status_id: statuses(:goal_work).id, position: 0 },
      headers: bearer(@fish_token), as: :json
    assert_response :success
    assert_equal statuses(:goal_work), target.reload.status

    delete api_project_task_path(@goal, target.id), headers: bearer(@fish_token)
    assert_response :no_content
    assert target.reload.archived?
  end

  test "an agent assigns a person: the person gets the usual email, naming the agent" do
    target = task("Blocked", assignee: @fish.user)

    perform_enqueued_jobs do
      patch api_project_task_path(@goal, target.id), params: { assignee_id: users(:two).id }, headers: bearer(@fish_token), as: :json
    end

    assert_response :success
    mail = ActionMailer::Base.deliveries.sole
    assert_equal [ "two@example.com" ], mail.to
    assert_equal "Fish assigned #{target.key} to you", mail.subject
  end

  test "an agent assigning another agent sends nothing" do
    target = task("Hand over", assignee: @fish.user)

    assert_no_enqueued_emails do
      patch api_project_task_path(@goal, target.id), params: { assignee_id: @owl.user.id }, headers: bearer(@fish_token), as: :json
    end

    assert_response :success
  end

  # Tasks assigned to the requester

  test "an agent's work: its open tasks and subtasks by column and number, with each subtask's parent" do
    done = task("Done", assignee: @fish.user, status: statuses(:goal_done))
    in_work = task("In work", assignee: @fish.user, status: statuses(:goal_work))
    task("Owl's", assignee: @owl.user)
    subtask = task("Subtask", assignee: @fish.user, parent: in_work)
    task("Archived", assignee: @fish.user).archive!
    task("Unassigned")

    tasks = assigned(@fish_token)

    assert_equal [ subtask.key, in_work.key ], tasks.map { |card| card["key"] }
    assert_equal [ in_work.id, nil ], tasks.map { |card| card["parent_id"] }
    assert_not_includes tasks.map { |card| card["id"] }, done.id
    assert_equal [ "Owl's" ], assigned(@owl_token).map { |card| card["title"] }
  end

  test "within a column, tasks are listed by number" do
    first = task("First", assignee: @fish.user)
    second = task("Second", assignee: @fish.user)
    first.update!(position: 1) && second.update!(position: 0)

    assert_equal [ first.number, second.number ], assigned(@fish_token).map { |card| card["number"] }
  end

  test "in a change and in none: a person's tasks are listed whatever their change" do
    change = @goal.project_changes.create!(name: "fix-login")
    in_none = task("In no change", assignee: users(:two))
    in_change = task("In the change", assignee: users(:two), change: change)
    sign_in_as users(:two)

    assert_equal [ in_none.id, in_change.id ], assigned.map { |card| card["id"] }
  end

  test "the view is per project and reaches only the token's projects" do
    side = projects(:side)
    side.memberships.create!(user: @fish.user)
    there = side.tasks.create!(title: "There", creator: users(:two), assignee: @fish.user, status: side.first_status)
    task("Here", assignee: @fish.user)

    assert_equal [ there.id ], assigned(@fish_token, project: side).map { |card| card["id"] }

    get api_project_tasks_path(side, view: "assigned"), headers: bearer(issue_agent_token(@fish, issuer: users(:one)))
    assert_response :not_found
  end

  # Deleted agents

  test "assign to a deleted agent: a validation error, and the task is unchanged" do
    target = task("Ship it", assignee: users(:two))
    @owl.delete!

    patch api_project_task_path(@goal, target.id), params: { assignee_id: @owl.user.id, title: "Renamed" }, headers: bearer(@fish_token), as: :json

    assert_response :unprocessable_content
    assert_equal [ "Assignee has been deleted" ], response.parsed_body.dig("error", "fields", "assignee")
    assert_equal [ users(:two).id, "Ship it" ], target.reload.values_at(:assignee_id, :title)

    post api_project_tasks_path(@goal), params: { title: "New", assignee_id: @owl.user.id }, headers: bearer(@fish_token), as: :json
    assert_response :unprocessable_content
  end

  test "a done task assigned to a deleted agent can still be edited" do
    target = task("Finished", assignee: @owl.user, status: statuses(:goal_done))
    @owl.delete!
    sign_in_as users(:one)

    patch api_project_task_path(@goal, target.id), params: { title: "Finished and reviewed" }, as: :json

    assert_response :success
    assert_equal @owl.user.id, target.reload.assignee_id
  end

  # Teammates and statistics

  test "agent teammates: an agent is a teammate, marked as one, and a deleted agent is not" do
    @owl.delete!
    sign_in_as users(:one)

    get api_teammates_path

    assert_equal [ [ "Fish", true ], [ "User Two", false ] ], response.parsed_body.map { |teammate| teammate.values_at("name", "agent") }
  end

  test "an agent's overview is a teammate's overview, and a deleted agent's is a 404" do
    task("Fish's work", assignee: @fish.user)
    task("Owl's work", assignee: @owl.user)
    sign_in_as users(:one)

    get api_statistics_overview_path(user_id: @fish.user.id)
    assert_response :success
    assert_equal [ "Fish's work" ], response.parsed_body.sole["columns"].flat_map { |column| column["tasks"] }.map { |t| t["title"] }

    @owl.delete!
    get api_statistics_overview_path(user_id: @owl.user.id)
    assert_response :not_found
  end

  # Cards are loaded with what they need (decision 8)

  test "the board, the member list and the comment list take the same number of queries however many agents there are" do
    target = task("Busy")
    [ @fish, @owl ].each { |agent| target.comments.create!(author: agent.user, body: "Noted") }
    sign_in_as users(:one)
    requests = {
      board: -> { get api_project_board_path(@goal) },
      members: -> { get api_project_members_path(@goal) },
      comments: -> { get api_project_task_comments_path(@goal, target.id) },
      agents: -> { get api_project_agents_path(@goal) },
      teammates: -> { get api_teammates_path }
    }
    requests.each_value(&:call) # warm up
    before = requests.transform_values { |request| count_queries(&request) }

    4.times do |i|
      agent = create_agent(@goal, name: "Agent #{i}")
      target.comments.create!(author: agent.user, body: "Noted")
    end

    requests.each do |name, request|
      assert_equal before[name], count_queries(&request), "#{name} runs more queries with more agents"
    end
  end

  # Counts cached queries too: the query cache spans a whole test case, but
  # only one request in production.
  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
