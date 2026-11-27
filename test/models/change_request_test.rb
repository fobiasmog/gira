require "test_helper"

# Spec change-requests: "Requests for the steps of a change", "Ask for a
# step", "Agent of a change", "Release an agent", "Full context", "Reply
# requests", "Take a request", "Finish a request", "Cancel a request" and
# "Check-ins"; spec changes, "Archive a change", "Change history" and
# "Waiting for people"; add-change-requests design.md, decisions 1 to 5, 7 to
# 10 and 13.
class ChangeRequestTest < ActiveSupport::TestCase
  setup do
    @project = projects(:goal)
    @member = users(:one)
    @fish = create_agent(@project, name: "Fish").user
    @heron = create_agent(@project, name: "Heron").user
  end

  def create_change(name, **attributes) = @project.project_changes.create!(name:, **attributes)

  def ask(change, kind, by: @member, **options) = ChangeRequest.ask!(change:, kind:, by:, **options)

  def take(agent) = ChangeRequest.take!(project: @project, agent:)

  # agent is on change, as after taking its first request.
  def put_on(change, agent)
    change.update!(agent:, agent_taken_at: Time.current)
    change
  end

  # A failing statement inside it leaves the test's transaction usable.
  def savepoint(&) = ActiveRecord::Base.transaction(requires_new: true, &)

  def assert_refused(attribute, &block)
    error = assert_raises(ActiveRecord::RecordInvalid, &block)
    assert error.record.errors.include?(attribute), "expected an error on #{attribute}, got #{error.record.errors.to_hash}"
  end

  # Database

  test "the database refuses a second open request on one change, and keeps finished ones" do
    change = create_change("export-csv")
    change.requests.create!(kind: "explore", requested_by: @member, state: "done")
    change.requests.create!(kind: "propose", requested_by: @member)

    assert_raises(ActiveRecord::RecordNotUnique) { savepoint { change.requests.create!(kind: "implement", requested_by: @member, state: "taken") } }
    assert_raises(ActiveRecord::StatementInvalid) { savepoint { change.requests.new(kind: "deploy", requested_by: @member).save!(validate: false) } }
  end

  test "the database refuses one agent on two open changes, and an archived change does not count" do
    archived = put_on(create_change("fix-login"), @fish)
    archived.update_column(:archived_at, Time.current)
    put_on(create_change("export-csv"), @fish)

    tags = create_change("add-tags")
    theirs = projects(:side).project_changes.create!(name: "theirs")
    assert_raises(ActiveRecord::RecordNotUnique) { savepoint { tags.update_columns(agent_id: @fish.id, agent_taken_at: Time.current) } }
    assert_raises(ActiveRecord::RecordNotUnique) { savepoint { theirs.update_columns(agent_id: @fish.id, agent_taken_at: Time.current) } }
    assert_raises(ActiveRecord::StatementInvalid) { savepoint { tags.update_columns(agent_id: nil, agent_taken_at: Time.current) } }
  end

  # Requests for the steps of a change

  test "one open request: asking for another step is refused, and the first one stays alone" do
    change = create_change("export-csv")
    explore = ask(change, "explore")

    assert_refused(:base) { ask(change, "propose") }
    assert_equal [ explore ], change.requests.reload.to_a
  end

  test "request after a finished one: the new one waits, and the finished one stays done" do
    change = create_change("export-csv")
    explore = ask(change, "explore")
    take(@fish).finish!(by: @fish, outcome: "done", comment: "Explored.")

    propose = ask(change, "propose")

    assert_equal [ "done", "waiting" ], [ explore.reload.state, propose.state ]
    assert_equal propose, change.reload.open_request
  end

  # Ask for a step

  test "start exploring: a waiting explore request asked for by the member, and the change still in Idea" do
    change = create_change("export-csv")

    request = ask(change, "explore")

    assert_equal [ "explore", "waiting", @member ], [ request.kind, request.state, request.requested_by ]
    assert_equal "idea", change.reload.phase
    assert_nil request.taken_at
  end

  test "with a comment: posted by the member, with the request as the only open one, and no reply request" do
    change = create_change("export-csv", phase: "proposed")

    ask(change, "implement", comment: "Start with the API.")

    assert_equal [ [ "Start with the API.", @member ] ], change.comments.map { |comment| [ comment.body, comment.author ] }
    assert_equal [ "implement" ], change.requests.unfinished.pluck(:kind)
  end

  test "an empty or too long comment is refused on the comment, and nothing is created" do
    change = create_change("export-csv")

    [ "", "a" * 10_001 ].each do |comment|
      assert_refused(:comment) { ask(change, "explore", comment:) }
    end
    assert_empty change.requests
    assert_empty change.comments
  end

  test "replacing a reply request that is still waiting" do
    change = create_change("export-csv", phase: "exploring")
    reply = change.ask_reply_after(change.comments.create!(author: @member, body: "No archived tasks."))

    implement = ask(change, "implement")

    assert_equal [ "cancelled", @member ], [ reply.reload.state, reply.finished_by ]
    assert_equal implement, change.reload.open_request
  end

  test "taken request: asking for another step is refused, and the agent's request stays taken" do
    change = put_on(create_change("export-csv", phase: "exploring"), @fish)
    change.ask_reply_after(change.comments.create!(author: @member, body: "No."))
    reply = take(@fish)

    assert_refused(:base) { ask(change, "implement") }
    assert_equal [ "taken", @fish ], [ reply.reload.state, reply.taken_by ]
    assert_equal 1, change.requests.count
  end

  test "archived change: refused, and no request is created" do
    change = create_change("fix-login").tap(&:archive!)

    assert_refused(:base) { ask(change, "explore") }
    assert_empty change.requests
  end

  test "reply asked for directly, or an unknown kind: refused on the kind" do
    change = create_change("export-csv", phase: "exploring")

    [ "reply", "deploy", "" ].each { |kind| assert_refused(:kind) { ask(change, kind) } }
    assert_empty change.requests
  end

  # Agent of a change

  test "pick when creating: in Idea with Fish picked, the idea still editable, and Fish's take returns nothing" do
    change = create_change("add-tags", idea: "Tags on tasks.", agent: @fish)

    assert_equal [ "idea", @fish, false ], [ change.reload.phase, change.agent, change.agent_on? ]
    assert change.update(idea: "Tags on tasks and changes.")
    assert_nil take(@fish)
  end

  test "move to another agent: Heron is picked, and Fish's next take does not return the request" do
    change = create_change("add-tags", agent: @fish)
    request = ask(change, "explore")

    change.pick_agent!(@heron)

    assert_equal @heron, change.reload.agent
    assert_nil take(@fish)
    assert_equal request, take(@heron)
  end

  test "back to any free agent: the waiting request is in the shared pool" do
    change = create_change("add-tags", agent: @fish)
    request = ask(change, "explore")

    change.pick_agent!(nil)

    assert_nil change.reload.agent
    assert_equal request, take(@heron)
  end

  test "agent on the change: picking another is refused, and Fish stays on" do
    change = put_on(create_change("export-csv"), @fish)

    assert_refused(:agent) { change.pick_agent!(@heron) }
    assert_refused(:agent) { change.reload.pick_agent!(nil) }
    assert_equal [ @fish, true ], [ change.reload.agent, change.agent_on? ]
  end

  test "not an agent, a deleted agent, or an agent of another project: refused on the agent" do
    change = create_change("add-tags")
    owl = create_agent(@project, name: "Owl").tap(&:delete!).user
    stranger = create_agent(projects(:side), name: "Crow", created_by: users(:two)).user

    [ users(:two), owl, stranger ].each do |agent|
      assert_refused(:agent) { change.reload.pick_agent!(agent) }
    end
    assert_nil change.reload.agent
  end

  # Release an agent

  test "release while waiting for people: no agent, Fish is free, and the next request goes to the shared pool" do
    change = put_on(create_change("export-csv", phase: "exploring"), @fish)

    change.release_agent!(by: @member)

    assert_nil change.reload.agent
    assert_nil change.agent_taken_at
    request = ask(change, "propose")
    assert_equal request, take(@heron)
    assert_equal @heron, change.reload.agent
    other = ask(create_change("fix-login"), "explore")
    assert_equal other, take(@fish), "Fish is free again"
  end

  test "release during a step: the request is cancelled by the member, and Fish's next take does not return it" do
    change = create_change("export-csv", phase: "proposed")
    ask(change, "implement")
    request = take(@fish)

    change.release_agent!(by: @member)

    assert_equal [ "cancelled", @member ], [ request.reload.state, request.finished_by ]
    assert_nil change.reload.agent
    assert_nil take(@fish)
  end

  test "a release is recorded with the member and the released agent; a change with no agent is left as it is" do
    change = put_on(create_change("export-csv"), @fish)

    change.release_agent!(by: @member)
    assert_no_difference(-> { ChangeEvent.count }) { change.release_agent!(by: @member) }

    assert_equal [ [ "release", @member, @fish ] ], change.events.map { |event| [ event.kind, event.actor, event.agent ] }
  end

  test "release keeps a waiting request, which goes to the shared pool" do
    change = put_on(create_change("export-csv", phase: "exploring"), @fish)
    request = ask(change, "propose")

    change.release_agent!(by: @member)

    assert_equal "waiting", request.reload.state
    assert_equal request, take(@heron)
  end

  # Take a request

  test "oldest in the shared pool: Fish takes it, is on its change, which is in Exploring, and the other stays waiting" do
    login = create_change("fix-login")
    export = create_change("export-csv")
    older = travel_to(1.day.ago) { ask(login, "explore") }
    newer = ask(export, "explore")

    taken = take(@fish)

    assert_equal older, taken
    assert_equal [ "taken", @fish ], [ taken.state, taken.taken_by ]
    assert_not_nil taken.taken_at
    assert_equal [ @fish, true, "exploring" ], [ login.reload.agent, login.agent_on?, login.phase ]
    assert_equal "waiting", newer.reload.state
  end

  test "nothing waiting: no request" do
    assert_nil take(@fish)
  end

  test "resume: Fish gets its unfinished request again" do
    change = create_change("export-csv", phase: "proposed")
    ask(change, "implement")
    request = take(@fish)

    assert_equal request, take(@fish)
    assert_equal "taken", request.reload.state
  end

  test "a reply goes to the change's agent" do
    change = put_on(create_change("export-csv", phase: "exploring"), @fish)
    reply = change.ask_reply_after(change.comments.create!(author: @member, body: "No archived tasks."))

    assert_nil take(@heron)
    assert_equal reply, take(@fish)
  end

  test "busy agent: Fish gets nothing while on its change, and the other request stays waiting" do
    put_on(create_change("export-csv", phase: "exploring"), @fish)
    other = ask(create_change("rename-labels"), "explore")

    assert_nil take(@fish)
    assert_equal "waiting", other.reload.state
  end

  test "busy in another project: Fish gets nothing here" do
    projects(:side).memberships.create!(user: @fish)
    put_on(projects(:side).project_changes.create!(name: "theirs"), @fish)
    ask(create_change("rename-labels"), "explore")

    assert_nil take(@fish)
  end

  test "own queue first: Fish takes the change it is picked for before the older one in the shared pool" do
    rename = create_change("rename-labels")
    travel_to(1.day.ago) { ask(rename, "explore") }
    tags = create_change("add-tags", agent: @fish)
    request = ask(tags, "explore")

    assert_equal request, take(@fish)
    assert tags.reload.agent_on?
  end

  test "picked for another agent: Heron gets nothing" do
    ask(create_change("add-tags", agent: @fish), "explore")

    assert_nil take(@heron)
  end

  test "implement moves the phase to Implementing, recorded as Fish's move" do
    change = put_on(create_change("export-csv", phase: "proposed"), @fish)
    ask(change, "implement")

    take(@fish)

    assert_equal "implementing", change.reload.phase
    assert_equal [ [ "phase", "implementing", @fish ] ], change.events.map { |event| [ event.kind, event.phase, event.actor ] }
  end

  test "explore moves only a change in Idea; other kinds leave the phase" do
    exploring = put_on(create_change("export-csv", phase: "proposed"), @fish)
    ask(exploring, "explore")
    take(@fish)
    assert_equal "proposed", exploring.reload.phase

    proposing = put_on(create_change("fix-login", phase: "exploring"), @heron)
    ask(proposing, "propose")
    take(@heron)
    assert_equal "exploring", proposing.reload.phase
    assert_empty proposing.events
  end

  test "requests of archived changes and of other projects are never taken" do
    ask(create_change("export-csv"), "explore")
    @project.project_changes.find_by!(name: "export-csv").update_column(:archived_at, Time.current)
    projects(:side).memberships.create!(user: @fish)
    ask(projects(:side).project_changes.create!(name: "theirs"), "explore", by: users(:two))

    assert_nil take(@fish)
  end

  # Finish a request

  test "questions: done, the comment posted by Fish, and the change waiting for people" do
    change = create_change("export-csv")
    ask(change, "explore")
    request = take(@fish)

    request.finish!(by: @fish, outcome: "done", comment: "Two questions before I write the proposal: …")

    assert_equal [ "done", @fish ], [ request.reload.state, request.finished_by ]
    assert_not_nil request.finished_at
    assert_equal [ [ "Two questions before I write the proposal: …", @fish ] ], change.comments.map { |comment| [ comment.body, comment.author ] }
    assert change.reload.waiting_for_people?
    assert_nil change.open_request
  end

  test "failed: the request is failed, and the comment posted by Fish" do
    change = create_change("export-csv", phase: "proposed")
    ask(change, "implement")
    request = take(@fish)

    request.finish!(by: @fish, outcome: "failed", comment: "The system tests fail on the CSV download.")

    assert_equal "failed", request.reload.state
    assert_equal @fish, change.comments.sole.author
  end

  test "comment while working: a reply request asked for by the member who commented" do
    change = create_change("export-csv", phase: "proposed")
    travel_to(Time.zone.parse("2026-11-18 14:00")) { ask(change, "implement", comment: "Before taking") }
    request = travel_to(Time.zone.parse("2026-11-18 14:05")) { take(@fish) }
    travel_to(Time.zone.parse("2026-11-18 14:20")) do
      comment = change.comments.create!(author: users(:two), body: "Also handle empty files.")
      assert_nil change.ask_reply_after(comment)
    end

    travel_to(Time.zone.parse("2026-11-18 15:00")) { request.finish!(by: @fish, outcome: "done", comment: "Implemented.") }

    reply = change.reload.open_request
    assert_equal [ "reply", "waiting", users(:two) ], [ reply.kind, reply.state, reply.requested_by ]
    assert_not change.waiting_for_people?
  end

  test "archive: the comment is posted, the change is archived, and Fish is free" do
    change = put_on(create_change("export-csv", phase: "implementing"), @fish)
    ask(change, "archive")
    request = take(@fish)

    request.finish!(by: @fish, outcome: "done", comment: "Archived the OpenSpec change and synced its specs.")

    assert change.reload.archived?
    assert_equal "done", request.reload.state
    assert_equal "Archived the OpenSpec change and synced its specs.", change.comments.sole.body
    other = ask(create_change("fix-login"), "explore")
    assert_equal other, take(@fish)
  end

  test "an archive request failed leaves the change open" do
    change = put_on(create_change("export-csv", phase: "implementing"), @fish)
    ask(change, "archive")

    take(@fish).finish!(by: @fish, outcome: "failed", comment: "openspec archive fails.")

    assert_not change.reload.archived?
  end

  test "cancelled meanwhile: refused, and no comment is posted" do
    change = create_change("export-csv")
    ask(change, "explore")
    request = take(@fish)
    request.cancel!(by: @member)

    assert_refused(:base) { request.finish!(by: @fish, outcome: "done", comment: "Done.") }
    assert_empty change.comments
    assert_equal "cancelled", request.reload.state
  end

  test "someone else's request: refused, and it stays taken by Fish" do
    change = create_change("export-csv")
    ask(change, "explore")
    request = take(@fish)

    assert_refused(:base) { ChangeRequest.find(request.id).finish!(by: @heron, outcome: "done", comment: "Mine now.") }
    assert_equal [ "taken", @fish ], [ request.reload.state, request.taken_by ]
    assert_empty change.comments
  end

  test "no comment or an unknown outcome: refused, and the request stays taken" do
    change = create_change("export-csv")
    ask(change, "explore")
    request = take(@fish)

    assert_refused(:comment) { request.finish!(by: @fish, outcome: "done", comment: nil) }
    assert_refused(:comment) { request.finish!(by: @fish, outcome: "done", comment: "") }
    assert_refused(:outcome) { request.finish!(by: @fish, outcome: "cancelled", comment: "Hm.") }
    assert_equal "taken", request.reload.state
    assert_empty change.comments
  end

  # Cancel a request

  test "cancel a waiting request: cancelled by the member, and no open request" do
    change = create_change("export-csv")
    request = ask(change, "explore")

    request.cancel!(by: @member)

    assert_equal [ "cancelled", @member ], [ request.reload.state, request.finished_by ]
    assert_nil change.reload.open_request
  end

  test "cancel a taken request: Fish's next take does not return it, and Fish is still on the change" do
    change = create_change("export-csv", phase: "proposed")
    ask(change, "implement")
    request = take(@fish)

    request.cancel!(by: @member)

    assert_equal "cancelled", request.reload.state
    assert_nil take(@fish)
    assert_equal [ @fish, true ], [ change.reload.agent, change.agent_on? ]
  end

  test "cancel a finished request: it stays done" do
    change = create_change("export-csv")
    ask(change, "explore")
    request = take(@fish).finish!(by: @fish, outcome: "done", comment: "Done.")

    request.cancel!(by: @member)

    assert_equal [ "done", @fish ], [ request.reload.state, request.finished_by ]
  end

  # Check-ins

  test "every take is the agent's check-in in the project, whether it returns a request or not" do
    membership = @project.memberships.find_by!(user: @fish)
    assert_nil membership.checked_in_at
    assert_not Agent.online?(membership.checked_in_at)

    travel_to(Time.zone.parse("2026-11-18 14:00")) { assert_nil take(@fish) }
    assert_equal Time.zone.parse("2026-11-18 14:00"), membership.reload.checked_in_at
    travel_to(Time.zone.parse("2026-11-18 14:02")) { assert Agent.online?(membership.checked_in_at) }
    travel_to(Time.zone.parse("2026-11-18 14:03")) { assert_not Agent.online?(membership.checked_in_at) }

    ask(create_change("export-csv"), "explore")
    travel_to(Time.zone.parse("2026-11-18 16:00")) { assert take(@fish) }
    assert_equal Time.zone.parse("2026-11-18 16:00"), membership.reload.checked_in_at
  end

  # Reply requests

  test "answer to an agent's questions: a reply request asked for by the member" do
    change = create_change("export-csv")
    ask(change, "explore")
    take(@fish).finish!(by: @fish, outcome: "done", comment: "Archived tasks too?")

    reply = change.reload.ask_reply_after(change.comments.create!(author: @member, body: "No archived tasks."))

    assert_equal [ "reply", "waiting", @member ], [ reply.kind, reply.state, reply.requested_by ]
    assert_equal reply, change.reload.open_request
  end

  test "an agent's comment, a comment in Idea, and a comment on an archived change create no request" do
    exploring = create_change("export-csv", phase: "exploring")
    idea = create_change("fix-login")
    archived = create_change("add-tags", phase: "exploring")
    late = archived.comments.create!(author: @member, body: "Late")
    archived.archive!

    assert_nil exploring.ask_reply_after(exploring.comments.create!(author: @fish, body: "Question"))
    assert_nil idea.ask_reply_after(idea.comments.create!(author: @member, body: "Thoughts"))
    assert_nil archived.ask_reply_after(late)
    assert_empty ChangeRequest.all
  end

  test "comment while a request is taken: no request yet, and the implement request stays taken by Fish" do
    change = create_change("export-csv", phase: "proposed")
    ask(change, "implement")
    request = take(@fish)

    assert_nil change.ask_reply_after(change.comments.create!(author: @member, body: "Also handle empty files."))

    assert_equal [ request ], change.requests.to_a
    assert_equal [ "taken", @fish ], [ request.reload.state, request.taken_by ]
  end

  test "a comment posted while asking for a step creates no reply request" do
    change = create_change("export-csv", phase: "exploring")

    ask(change, "propose", comment: "Write it up.")

    assert_equal [ "propose" ], change.requests.pluck(:kind)
  end

  # Waiting for people

  test "request open: not waiting while the request is open, whatever the newest comment" do
    change = create_change("export-csv", phase: "proposed")
    change.comments.create!(author: @fish, body: "Should archived tasks go into the file?")
    assert change.waiting_for_people?

    request = ask(change, "implement")
    assert_not change.reload.waiting_for_people?
    take(@fish)
    assert_not change.reload.waiting_for_people?

    request.reload.cancel!(by: @member)
    assert change.reload.waiting_for_people?
  end

  # Archive a change

  test "archive with an open request: archived, the request cancelled by the member, and Fish free" do
    change = create_change("export-csv", phase: "proposed")
    ask(change, "implement")
    request = take(@fish)

    change.archive!(by: @member)

    assert change.reload.archived?
    assert_equal [ "cancelled", @member ], [ request.reload.state, request.finished_by ]
    other = ask(create_change("fix-login"), "explore")
    assert_equal other, take(@fish)
  end

  # Full context

  test "full during a step: Fish is blocked, the change waits for people with its block in the history, and the request stays taken" do
    change = create_change("export-csv", phase: "proposed")
    ask(change, "implement")
    request = take(@fish)

    assert Change.block_for_full_context!(project: @project, agent: @fish)

    assert change.reload.blocked?
    assert change.waiting_for_people?
    assert_equal [ "block", @fish ], change.events.last.then { |event| [ event.kind, event.actor ] }
    assert_equal [ "taken", @fish ], [ request.reload.state, request.taken_by ]
  end

  test "full twice: blocked, with the block recorded once" do
    put_on(create_change("export-csv"), @fish)

    assert Change.block_for_full_context!(project: @project, agent: @fish)
    assert Change.block_for_full_context!(project: @project, agent: @fish)

    assert_equal 1, ChangeEvent.where(kind: "block").count
  end

  test "full while free, or while on a change of another project: not blocked, and nothing changes" do
    picked = create_change("add-tags", agent: @heron)

    assert_no_difference(-> { ChangeEvent.count }) do
      assert_not Change.block_for_full_context!(project: @project, agent: @heron)
    end
    assert_not picked.reload.blocked?

    projects(:side).memberships.create!(user: @fish)
    put_on(projects(:side).project_changes.create!(name: "theirs"), @fish)
    assert_not Change.block_for_full_context!(project: @project, agent: @fish)
  end

  test "blocked change: Fish gets no request, and the implement request stays taken" do
    change = create_change("export-csv", phase: "proposed")
    ask(change, "implement")
    request = take(@fish)
    Change.block_for_full_context!(project: @project, agent: @fish)
    ask(create_change("fix-login"), "explore")

    assert_nil take(@fish)
    assert_equal "taken", request.reload.state
  end

  test "blocked with no open request: a waiting request of the change is not given to Fish" do
    change = put_on(create_change("export-csv", phase: "exploring"), @fish)
    Change.block_for_full_context!(project: @project, agent: @fish)
    change.ask_reply_after(change.comments.create!(author: @member, body: "Go on."))

    assert_nil take(@fish)
    assert_nil take(@heron)
    assert change.reload.waiting_for_people?
  end

  test "release after a block: Heron takes the next implement request, and the change is no longer blocked" do
    change = create_change("export-csv", phase: "proposed")
    ask(change, "implement")
    take(@fish)
    Change.block_for_full_context!(project: @project, agent: @fish)

    change.release_agent!(by: @member)
    request = ask(change, "implement")

    assert_equal request, take(@heron)
    assert_equal [ @heron, false ], [ change.reload.agent, change.blocked? ]
    assert_not change.waiting_for_people?
  end

  # Session of a stint (spec agent-workspaces; add-runners-and-workspaces
  # design.md, decision 3)

  UUID_V4 = /\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/

  test "first take: the agent's stint gets a session" do
    change = create_change("export-csv")
    ask(change, "explore")

    take(@fish)

    assert_match UUID_V4, change.reload.agent_session_id
  end

  test "later request of the stint: the same session" do
    change = create_change("export-csv")
    ask(change, "explore")
    take(@fish).finish!(by: @fish, outcome: "done", comment: "Questions.")
    session = change.reload.agent_session_id

    ask(change, "propose")
    take(@fish)
    assert_equal session, change.reload.agent_session_id
    assert_equal session, take(@fish).change.agent_session_id
  end

  test "new stint: released, then Heron takes the next request with another session" do
    change = create_change("export-csv")
    ask(change, "explore")
    take(@fish).finish!(by: @fish, outcome: "done", comment: "Questions.")
    fish_session = change.reload.agent_session_id

    change.release_agent!(by: @member)
    assert_nil change.reload.agent_session_id
    ask(change, "propose")
    take(@heron)

    assert_match UUID_V4, change.reload.agent_session_id
    assert_not_equal fish_session, change.agent_session_id
  end

  test "archived: the stint's session ends" do
    change = create_change("export-csv")
    ask(change, "explore")
    take(@fish)

    change.archive!(by: @member)

    assert_nil change.reload.agent_session_id
    assert_equal @fish, change.agent
  end

  test "an agent on a change without a session gets one on its next take, for a taken or a waiting request" do
    taken = put_on(create_change("export-csv"), @fish)
    taken.requests.create!(kind: "implement", requested_by: @member, state: "taken", taken_by: @fish, taken_at: Time.current)
    take(@fish)
    assert_match UUID_V4, taken.reload.agent_session_id

    waiting = put_on(create_change("add-tags"), @heron)
    ask(waiting, "propose")
    take(@heron)
    assert_match UUID_V4, waiting.reload.agent_session_id
  end

  # Take a request: workspaces (add-runners-and-workspaces design.md,
  # decision 3)

  def runner(name) = Runner.issue(user: @member, name:).tap(&:save!)

  def workspace(change, runner)
    Workspace.create!(change:, runner:, path: "/home/bob/goalner/workspaces/GOAL/#{change.name}", branch: change.name, base_branch: "main")
  end

  test "workspace on another runner: a run token of another runner gets no request, and it stays waiting" do
    laptop = runner("laptop")
    change = create_change("export-csv")
    workspace(change, laptop)
    implement = ask(change, "implement")

    assert_nil ChangeRequest.take!(project: @project, agent: @heron, runner: runner("desktop"))
    assert_equal "waiting", implement.reload.state
    assert_equal implement, ChangeRequest.take!(project: @project, agent: @heron, runner: laptop)
  end

  test "token that is not a run token: no request of a change with an active workspace, in any step" do
    laptop = runner("laptop")
    change = create_change("export-csv")
    ask(change, "explore")
    take(@fish).finish!(by: @fish, outcome: "done", comment: "Questions.")
    workspace(change, laptop)
    reply = change.requests.create!(kind: "reply", requested_by: @member)

    assert_nil take(@fish)
    assert_equal "waiting", reply.reload.state

    assert_equal reply, ChangeRequest.take!(project: @project, agent: @fish, runner: laptop)
    assert_nil take(@fish)
    assert_equal reply, ChangeRequest.take!(project: @project, agent: @fish, runner: laptop)
  end

  test "a workspace that is no longer active keeps no change away" do
    laptop = runner("laptop")
    change = create_change("export-csv")
    workspace(change, laptop).update_column(:state, "kept")
    explore = ask(change, "explore")

    assert_equal explore, take(@fish)
  end
end
