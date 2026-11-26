require "test_helper"

# Spec change-requests, "Take a request", "Finish a request", "Cancel a
# request" and "Full context"; add-change-requests design.md, decisions 3, 6,
# 7 and 13. Agents act through their tokens, members through their session.
class Api::Projects::RequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:goal)
    @fish = create_agent(@project, name: "Fish")
    @heron = create_agent(@project, name: "Heron")
    sign_in_as users(:one)
  end

  def token_of(agent) = bearer(issue_agent_token(agent, issuer: users(:one)))
  def fish = @fish_token ||= token_of(@fish)
  def heron = @heron_token ||= token_of(@heron)

  def create_change(name, **attributes) = @project.project_changes.create!(name:, **attributes)
  def ask(change, kind) = ChangeRequest.ask!(change:, kind:, by: users(:one))

  def claim(headers)
    post claim_api_project_requests_path(@project), headers:, as: :json
    assert_response :ok
    response.parsed_body.fetch("request")
  end

  def finish(request, headers:, **params)
    post finish_api_project_request_path(@project, request), params:, headers:, as: :json
  end

  # Take a request

  test "oldest in the shared pool: Fish gets it with its change and phase, and is on the change" do
    login = create_change("fix-login")
    export = create_change("export-csv")
    travel_to(1.day.ago) { ask(login, "explore") }
    newer = ask(export, "explore")

    taken = claim(fish)

    assert_equal [ "explore", "taken", "Fish", "User One" ], [ taken["kind"], taken["state"], taken.dig("taken_by", "name"), taken.dig("requested_by", "name") ]
    assert_equal({ "id" => login.id, "name" => "fix-login", "phase" => "exploring" }, taken["change"])
    assert taken["taken_at"].present?
    assert_equal @fish.user, login.reload.agent
    assert_equal "waiting", newer.reload.state
  end

  test "nothing waiting: 200 with no request" do
    post claim_api_project_requests_path(@project), headers: fish, as: :json

    assert_response :ok
    assert_equal({ "request" => nil }, response.parsed_body)
  end

  test "resume: Fish gets its unfinished implement request again" do
    change = create_change("export-csv", phase: "proposed")
    ask(change, "implement")
    first = claim(fish)

    assert_equal first["id"], claim(fish)["id"]
  end

  test "a reply goes to the change's agent: Heron gets none, Fish gets it" do
    change = create_change("export-csv")
    ask(change, "explore")
    claim(fish)
    post finish_api_project_request_path(@project, change.requests.sole), params: { outcome: "done", comment: "Questions?" }, headers: fish, as: :json
    post api_project_change_comments_path(@project, "export-csv"), params: { body: "No archived tasks." }, as: :json

    assert_nil claim(heron)
    assert_equal "reply", claim(fish)["kind"]
  end

  test "busy agent, own queue first and picked for another agent" do
    busy = create_change("export-csv", phase: "exploring")
    busy.update!(agent: @fish.user, agent_taken_at: Time.current)
    travel_to(1.day.ago) { ask(create_change("rename-labels"), "explore") }
    tags = create_change("add-tags", agent: @heron.user)
    ask(tags, "explore")

    assert_nil claim(fish), "busy"
    assert_equal "add-tags", claim(heron).dig("change", "name"), "own queue first"
    owl = create_agent(@project, name: "Owl")
    assert_equal "rename-labels", claim(token_of(owl)).dig("change", "name")
  end

  test "picked for another agent: Heron gets nothing" do
    ask(create_change("add-tags", agent: @fish.user), "explore")

    assert_nil claim(heron)
  end

  test "implement moves the phase, and the history lists Fish's move" do
    change = create_change("export-csv", phase: "proposed", agent: @fish.user)
    ask(change, "implement")

    assert_equal "implementing", claim(fish).dig("change", "phase")

    get api_project_change_path(@project, "export-csv")
    assert_includes response.parsed_body["history"].map { |entry| entry.values_at("kind", "phase") + [ entry.dig("actor", "name") ] }, [ "phase", "implementing", "Fish" ]
  end

  test "a person takes: 403 agents_only, and the request stays waiting" do
    request = ask(create_change("export-csv"), "explore")

    post claim_api_project_requests_path(@project), as: :json

    assert_response :forbidden
    assert_equal "agents_only", response.parsed_body.dig("error", "code")
    assert_equal "waiting", request.reload.state
    post claim_api_project_requests_path(@project), headers: bearer("glnr_two_goal_read_write"), as: :json
    assert_response :forbidden
    assert_equal "agents_only", response.parsed_body.dig("error", "code")
  end

  test "blocked change: Fish gets no request, and the implement request stays taken" do
    change = create_change("export-csv", phase: "proposed")
    ask(change, "implement")
    claim(fish)
    post context_full_api_project_requests_path(@project), headers: fish, as: :json

    assert_nil claim(fish)
    assert_equal "taken", change.requests.sole.state
  end

  test "every take checks the agent in, whether it returns a request or not" do
    travel_to(Time.zone.parse("2026-11-18 14:00")) { claim(fish) }

    assert_equal Time.zone.parse("2026-11-18 14:00"), @project.memberships.find_by!(user: @fish.user).checked_in_at
  end

  # Finish a request

  test "questions: done, the comment posted by Fish, and the change waiting for people" do
    change = create_change("export-csv")
    ask(change, "explore")
    taken = claim(fish)

    finish taken["id"], headers: fish, outcome: "done", comment: "Two questions before I write the proposal: …"

    assert_response :ok
    assert_equal [ "done", "Fish" ], [ response.parsed_body["state"], response.parsed_body.dig("finished_by", "name") ]
    assert_equal [ [ "Two questions before I write the proposal: …", @fish.user ] ], change.comments.map { |c| [ c.body, c.author ] }
    get api_project_change_path(@project, "export-csv")
    assert_equal [ true, nil ], response.parsed_body.values_at("waiting_for_people", "request")
  end

  test "failed: the request is failed, and the comment is Fish's" do
    change = create_change("export-csv", phase: "proposed")
    ask(change, "implement")

    finish claim(fish)["id"], headers: fish, outcome: "failed", comment: "The system tests fail on the CSV download."

    assert_response :ok
    assert_equal "failed", response.parsed_body["state"]
    assert_equal @fish.user, change.comments.sole.author
  end

  test "comment while working: a reply request asked for by the member" do
    change = create_change("export-csv", phase: "proposed")
    ask(change, "implement")
    taken = travel_to(Time.zone.parse("2026-11-18 14:05")) { claim(fish) }
    travel_to(Time.zone.parse("2026-11-18 14:20")) do
      post api_project_change_comments_path(@project, "export-csv"), params: { body: "Also handle empty files." }, as: :json
    end

    travel_to(Time.zone.parse("2026-11-18 15:00")) { finish taken["id"], headers: fish, outcome: "done", comment: "Implemented." }

    assert_response :ok
    assert_equal [ "reply", "waiting", users(:one) ], change.reload.open_request.then { |r| [ r.kind, r.state, r.requested_by ] }
  end

  test "archive: the comment is posted, the change is archived, and Fish is free" do
    change = create_change("export-csv", phase: "implementing")
    ask(change, "archive")

    finish claim(fish)["id"], headers: fish, outcome: "done", comment: "Archived the OpenSpec change and synced its specs."

    assert_response :ok
    assert change.reload.archived?
    assert_equal "Archived the OpenSpec change and synced its specs.", change.comments.sole.body
    ask(create_change("fix-login"), "explore")
    assert_equal "fix-login", claim(fish).dig("change", "name")
  end

  test "cancelled meanwhile: 422, and no comment is posted" do
    change = create_change("export-csv")
    ask(change, "explore")
    taken = claim(fish)
    post cancellation_api_project_request_path(@project, taken["id"]), as: :json

    finish taken["id"], headers: fish, outcome: "done", comment: "Done."

    assert_response :unprocessable_content
    assert response.parsed_body.dig("error", "fields", "base").present?
    assert_empty change.comments
  end

  test "someone else's request: 422, and it stays taken by Fish" do
    change = create_change("export-csv")
    ask(change, "explore")
    taken = claim(fish)

    finish taken["id"], headers: heron, outcome: "done", comment: "Mine now."

    assert_response :unprocessable_content
    assert_equal [ "taken", @fish.user ], change.requests.sole.then { |r| [ r.state, r.taken_by ] }
  end

  test "no comment: 422 on the comment, and the request stays taken" do
    change = create_change("export-csv")
    ask(change, "explore")

    finish claim(fish)["id"], headers: fish, outcome: "done"

    assert_response :unprocessable_content
    assert response.parsed_body.dig("error", "fields", "comment").present?
    assert_equal "taken", change.requests.sole.state
  end

  test "a request of another project: 404" do
    foreign = projects(:side).project_changes.create!(name: "theirs")
    request = ChangeRequest.ask!(change: foreign, kind: "explore", by: users(:two))

    post cancellation_api_project_request_path(@project, request), as: :json
    assert_response :not_found
    post cancellation_api_project_request_path(projects(:side), request), as: :json
    assert_response :not_found
    assert_equal "waiting", request.reload.state
  end

  # Cancel a request

  test "cancel a waiting request: cancelled by the member, and no open request" do
    change = create_change("export-csv")
    request = ask(change, "explore")

    post cancellation_api_project_request_path(@project, request), as: :json

    assert_response :ok
    assert_equal [ "cancelled", "User One" ], [ response.parsed_body["state"], response.parsed_body.dig("finished_by", "name") ]
    assert_nil change.reload.open_request
  end

  test "cancel a taken request: Fish's next take does not return it, and Fish is still on the change" do
    change = create_change("export-csv", phase: "proposed")
    ask(change, "implement")
    taken = claim(fish)

    post cancellation_api_project_request_path(@project, taken["id"]), as: :json

    assert_response :ok
    assert_nil claim(fish)
    assert_equal [ @fish.user, true ], [ change.reload.agent, change.agent_on? ]
  end

  test "cancel a finished request: it stays done" do
    change = create_change("export-csv")
    ask(change, "explore")
    taken = claim(fish)
    finish taken["id"], headers: fish, outcome: "done", comment: "Done."

    post cancellation_api_project_request_path(@project, taken["id"]), as: :json

    assert_response :ok
    assert_equal [ "done", "Fish" ], [ response.parsed_body["state"], response.parsed_body.dig("finished_by", "name") ]
  end

  # Full context

  test "full during a step: blocked, the change waiting for people with the block in its history, and the request still taken" do
    change = create_change("export-csv", phase: "proposed")
    ask(change, "implement")
    claim(fish)

    post context_full_api_project_requests_path(@project), headers: fish, as: :json

    assert_response :ok
    assert_equal({ "blocked" => true }, response.parsed_body)
    get api_project_change_path(@project, "export-csv")
    body = response.parsed_body
    assert_equal true, body["waiting_for_people"]
    assert body.dig("agent", "blocked_at").present?
    assert_equal [ "block", "Fish" ], body["history"].last.then { |entry| [ entry["kind"], entry.dig("actor", "name") ] }
    assert_equal [ "taken", "Fish" ], [ body.dig("request", "state"), body.dig("request", "taken_by", "name") ]
  end

  test "full while free: not blocked, and nothing changes" do
    assert_no_difference(-> { ChangeEvent.count }) do
      post context_full_api_project_requests_path(@project), headers: heron, as: :json
    end

    assert_response :ok
    assert_equal({ "blocked" => false }, response.parsed_body)
  end

  test "a person reports a full context: 403 agents_only" do
    post context_full_api_project_requests_path(@project), as: :json

    assert_response :forbidden
    assert_equal "agents_only", response.parsed_body.dig("error", "code")
  end

  test "release after a block: Heron gets the implement request and is on the change, which is no longer blocked" do
    change = create_change("export-csv", phase: "proposed")
    ask(change, "implement")
    claim(fish)
    post context_full_api_project_requests_path(@project), headers: fish, as: :json

    post api_project_change_agent_release_path(@project, "export-csv"), as: :json
    post api_project_change_requests_path(@project, "export-csv"), params: { kind: "implement" }, as: :json

    assert_equal "implement", claim(heron)["kind"]
    assert_equal [ @heron.user, false ], [ change.reload.agent, change.blocked? ]
  end
end
