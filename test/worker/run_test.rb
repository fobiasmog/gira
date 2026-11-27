require "test_helper"
require "support/goalner_worker_harness"

# Running requests (spec agent-worker, "Run a request", "One request per
# run", "Heartbeat and stopping a run", "After a run" and "Full context
# during a run"; add-runners-and-workspaces design.md, decision 5).
class GoalnerWorkerRunTest < ActiveSupport::TestCase
  include GoalnerWorkerHarness

  INSTRUCTIONS = File.read(Rails.root.join("lib/goalner_worker/instructions.md"))
  SESSION = "11111111-2222-4333-8444-555555555555".freeze

  setup do
    configure
  end

  def workspace_path = File.join(workspaces_root, "TEST", "export-csv")

  def run_one(*list, env: {})
    modes(*list)
    give_request(12)
    pid = start_worker(agent_id.to_s, env:)
    yield pid if block_given?
    pid
  end

  def finish_and_stop(pid)
    wait_until("the request to be finished") { @api.finished.any? }
    assert_equal 0, stop_worker(pid)
  end

  # Run a request

  test "first run of a stint: started in the workspace with --session-id, the instructions and the request" do
    pid = run_one("finish")
    finish_and_stop(pid)

    call = fake_calls.sole
    assert_equal workspace_path, File.realpath(call["cwd"])
    assert_equal SESSION, option(call, "--session-id")
    assert_nil option(call, "--resume")
    prompt = prompt_of(call)
    assert prompt.start_with?(INSTRUCTIONS)
    request = JSON.parse(prompt[/```json\n(.*?)\n```/m, 1])
    assert_equal [ 12, "explore", "export-csv", "main", SESSION, { "id" => 1, "short_name" => "TEST" } ],
      [ request["id"], request["kind"], request.dig("change", "name"), request.dig("change", "base_branch"), request.dig("change", "session_id"), request["project"] ]
    assert_equal Rails.root.join(".claude/goalner-worker.settings.json").to_s, option(call, "--settings")
    assert_equal Rails.root.join(".claude/goalner-worker.mcp.json").to_s, option(call, "--mcp-config")
    assert_includes call["args"], "--strict-mcp-config"
    assert_equal %w[stream-json], [ option(call, "--output-format") ]
    assert_includes call["args"], "--verbose"
    assert_not_includes call["args"], "--model"
  end

  test "the run's environment: the run token, Goalner's addresses, the worker's home and the change's database suffix, and no runner secret" do
    pid = run_one("finish")
    finish_and_stop(pid)

    call = fake_calls.sole
    assert_equal({ "GOALNER_TOKEN" => @api.leases.first["token"], "GOALNER_URL" => @api.url, "GOALNER_MCP_URL" => "http://127.0.0.1:1/mcp",
      "GOALNER_WORKER_HOME" => Rails.root.to_s, "GOALNER_TEST_DB_SUFFIX" => "c42" }, call["env"].except(*TIMINGS.keys))
    assert_equal false, call["secret_seen"]
  end

  test "later run of the stint: --resume with the same session, the same MCP configuration and settings, and no instructions" do
    modes("finish", "finish")
    give_request(12)
    pid = start_worker(agent_id.to_s)
    wait_until("the first request to be finished") { @api.finished.size == 1 }
    @api.synchronize { @api.waiting << StandInGoalner.request(13, kind: "reply") }
    wait_until("the reply request to be finished") { @api.finished.size == 2 }
    assert_equal 0, stop_worker(pid)

    first, later = fake_calls
    assert_equal [ SESSION, nil ], [ option(later, "--resume"), option(later, "--session-id") ]
    assert_equal first["args"].values_at(first["args"].index("--settings") + 1, first["args"].index("--mcp-config") + 1),
      later["args"].values_at(later["args"].index("--settings") + 1, later["args"].index("--mcp-config") + 1)
    assert_includes later["args"], "--strict-mcp-config"
    assert_not_includes prompt_of(later), INSTRUCTIONS
    assert_match(/"kind": "reply"/, prompt_of(later))
    assert_no_match(/## Notes/, prompt_of(later))
  end

  test "model and instructions: every run gets --model and --append-system-prompt" do
    @api.agent = @api.agent.merge("model" => "opus", "instructions" => "Keep commits small.")

    pid = run_one("finish")
    finish_and_stop(pid)

    call = fake_calls.sole
    assert_equal [ "opus", "Keep commits small." ], [ option(call, "--model"), option(call, "--append-system-prompt") ]
  end

  test "context lost: no transcript, and the stint took requests before, adds the note" do
    @api.earlier_takes = 1

    pid = run_one("finish")
    finish_and_stop(pid)

    assert_match(/Your earlier conversation on this change was lost/, prompt_of(fake_calls.sole))
    assert prompt_of(fake_calls.sole).start_with?(INSTRUCTIONS)
  end

  test "the log and the terminal: full output under log/agents, and a short form with the run's text, its tool calls, its duration and cost" do
    pid = run_one("finish")
    finish_and_stop(pid)

    log = Rails.root.join("log/agents", agent_id.to_s, "12.jsonl")
    lines = File.readlines(log).map { |line| JSON.parse(line) }
    assert_equal %w[system assistant result], lines.map { |line| line["type"] }
    output = output_of(pid)
    assert_match(/^\[\d\d:\d\d:\d\d\] Starting session #{SESSION} for the explore request 12 of export-csv/, output)
    assert_match(/^  Working on request 12\.$/, output)
    assert_match(/^  → Bash: git status$/, output)
    assert_match(/The run ended after 1m 1s, \$0\.25 for the session so far/, output)
    assert_not_includes output, StandInGoalner::SECRET
    assert_not_includes output, @api.leases.first["token"]
  end

  # One request per run

  test "finished by the run: the request is done with the run's comment, and the worker posts nothing" do
    pid = run_one("finish")
    finish_and_stop(pid)

    assert_equal [ { "id" => 12, "outcome" => "done", "comment" => "Did the explore step." } ], @api.finished
    assert_equal [ @api.leases.first["token"] ], @api.calls("POST", %r{/requests/12/finish}).map { |call| call[:token] }
  end

  # Heartbeat and stopping a run

  test "cancelled: the worker stops the run and waits for the next request" do
    pid = run_one("hang")
    wait_until("the run") { fake_calls.any? }

    @api.taken = nil
    wait_until("the run to be stopped") { !alive?(fake_calls.sole["pid"]) }

    assert alive?(pid)
    assert_match(/no longer Fish's.*Stopping the run/m, output_of(pid))
    assert_equal 0, stop_worker(pid)
    assert_empty @api.finished
  end

  test "released: the worker stops the run, and the workspace stays as it is" do
    pid = run_one("hang")
    wait_until("the run") { fake_calls.any? }
    File.write(File.join(workspace_path, "draft.md"), "work in progress\n")

    @api.taken = nil
    wait_until("the run to be stopped") { !alive?(fake_calls.sole["pid"]) }
    assert_equal 0, stop_worker(pid)

    assert_equal "work in progress\n", File.read(File.join(workspace_path, "draft.md"))
    assert_empty @api.calls("PATCH", /workspaces/).select { |call| call[:params].key?("state") }
  end

  test "another request: the worker stops the run, then runs that request" do
    pid = run_one("hang", "finish")
    wait_until("the run") { fake_calls.any? }

    @api.taken = StandInGoalner.request(20, kind: "reply")
    wait_until("request 20 to be finished") { @api.finished.any? }
    assert_equal 0, stop_worker(pid)

    assert_not alive?(fake_calls.first["pid"])
    assert_equal [ 20 ], @api.finished.map { |finished| finished["id"] }
    assert_match(/"id": 20/, prompt_of(fake_calls.last))
  end

  test "lease lapsed during a run: the worker leases Fish again, stops the run, and resumes the session with the new run token and the interrupted note" do
    pid = run_one("hang", "finish")
    wait_until("the run") { fake_calls.any? }

    @api.synchronize { @api.leases.each { |lease| lease["ended"] = true } }
    wait_until("the request to be finished") { @api.finished.any? }
    assert_equal 0, stop_worker(pid)

    first, second = fake_calls
    assert_equal 2, @api.leases.size
    assert_not alive?(first["pid"])
    assert_equal [ SESSION, @api.leases.last["token"] ], [ option(second, "--resume"), second.dig("env", "GOALNER_TOKEN") ]
    assert_match(/Your previous run of this request was interrupted/, prompt_of(second))
  end

  test "process ignores the interrupt: its process group is terminated" do
    pid = run_one("ignore_int")
    wait_until("the run") { fake_calls.any? }

    @api.taken = nil
    wait_until("the run to be stopped") { !alive?(fake_calls.sole["pid"]) }
    assert_equal 0, stop_worker(pid)
  end

  test "process ignores the interrupt and the termination: its process group is killed" do
    pid = run_one("ignore_int_term")
    wait_until("the run") { fake_calls.any? }

    @api.taken = nil
    wait_until("the run to be killed", timeout: 15) { !alive?(fake_calls.sole["pid"]) }
    assert_equal 0, stop_worker(pid)
  end

  # After a run

  test "dropped connection: a checkpoint is reported, and the same session resumes after the wait with the interrupted note" do
    pid = run_one("unfinished", "finish")
    finish_and_stop(pid)

    first, second = fake_calls
    assert_equal [ SESSION, SESSION ], [ option(first, "--session-id"), option(second, "--resume") ]
    assert_match(/Your previous run of this request was interrupted/, prompt_of(second))
    checkpoint = @api.checkpoints.first
    assert_equal [ git(workspace_path, "rev-parse", "HEAD").strip, false ], checkpoint.values_at("head_commit", "uncommitted")
    assert_equal "done", @api.finished.sole["outcome"]
  end

  test "three times: after the runs that continue the session after 1, 5 and 15 minutes are unfinished too, the request fails quoting the last run" do
    pid = run_one("unfinished", "unfinished", "unfinished", "unfinished")
    finish_and_stop(pid)

    assert_equal 4, fake_calls.size
    assert_equal [ nil, SESSION, SESSION, SESSION ], fake_calls.map { |call| option(call, "--resume") }
    failure = @api.finished.sole
    assert_equal "failed", failure["outcome"]
    assert_match(/ran this request 4 times.*error_during_execution: API Error: Connection error\./m, failure["comment"])
  end

  test "the count starts again for each request" do
    modes("unfinished", "finish", "unfinished", "unfinished", "finish")
    give_request(12)
    pid = start_worker(agent_id.to_s)
    wait_until("request 12 to be finished") { @api.finished.size == 1 }
    @api.synchronize { @api.waiting << StandInGoalner.request(13, kind: "reply") }
    wait_until("request 13 to be finished") { @api.finished.size == 2 }
    assert_equal 0, stop_worker(pid)

    assert_equal [ "done", "done" ], @api.finished.map { |finished| finished["outcome"] }
  end

  # Full context during a run

  test "context fills during a step: the change is blocked, the compaction does not run, the worker stops the run at once, and the request stays taken" do
    # A heartbeat far away: only the take after the reported compaction can stop the run in time.
    pid = run_one("context_full", env: { "GOALNER_WORKER_HEARTBEAT_SECONDS" => "60" })
    wait_until("the hook to run") { File.exist?(File.join(@tmp, "fake", "hook.json")) }
    hook = JSON.parse(File.read(File.join(@tmp, "fake", "hook.json")))

    wait_until("the run to be stopped", timeout: 8) { !alive?(fake_calls.sole["pid"]) }
    assert_equal 0, stop_worker(pid)

    assert_equal [ "auto", 2 ], hook.values_at("matcher", "exit"), hook["output"]
    assert_match(/Goalner blocked its change/, hook["output"])
    assert @api.blocked
    assert_equal [ @api.leases.first["token"] ], @api.calls("POST", /context_full/).map { |call| call[:token] }
    assert_equal 12, @api.taken["id"]
    assert_empty @api.finished
  end
end
