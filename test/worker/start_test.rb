require "test_helper"
require "support/goalner_worker_harness"

# Starting bin/goalner-worker <agent id> and waiting for requests (spec
# agent-worker, "Start an agent by its id", "Waiting for a request" and
# "Configuration file safety"; add-runners-and-workspaces design.md,
# decisions 5 and 6).
class GoalnerWorkerStartTest < ActiveSupport::TestCase
  include GoalnerWorkerHarness

  # Start an agent by its id

  test "no agent id: exit status 1, saying to create the agent in Goalner first and how to start it" do
    configure

    status, output = run_worker

    assert_equal 1, status
    assert_match(/Agents are created in Goalner first/, output)
    assert_match(/bin\/goalner-worker <agent id>/, output)
    assert_empty @api.requests
  end

  test "no runner configured, or several without --url naming one: exit status 1, without leasing" do
    status, output = run_worker(agent_id.to_s)
    assert_equal 1, status
    assert_match(/No runner is registered/, output)

    runner = { "secret" => StandInGoalner::SECRET, "name" => "laptop", "workspaces" => workspaces_root, "clones" => {} }
    configure(runners: [ runner.merge("url" => @api.url), runner.merge("url" => "https://goalner.com") ])
    status, output = run_worker(agent_id.to_s)
    assert_equal 1, status
    assert_match(/Choose one with --url/, output)
    status, = run_worker(agent_id.to_s, "--url", "https://elsewhere.example")
    assert_equal 1, status
    assert_empty @api.requests
  end

  test "--url chooses among several runners" do
    clone = create_clone
    runner = { "secret" => StandInGoalner::SECRET, "name" => "laptop", "workspaces" => workspaces_root, "clones" => { "TEST" => clone } }
    configure(runners: [ runner.merge("url" => "https://goalner.com"), runner.merge("url" => @api.url) ])

    pid = start_worker(agent_id.to_s, "--url", @api.url)
    wait_until("a lease") { @api.live_lease }

    assert_equal 0, stop_worker(pid)
  end

  test "leased elsewhere: exit status 1, saying Fish runs on desktop and since when" do
    configure
    @api.lease_refusal = [ 409, { "error" => { "code" => "agent_leased", "runner" => "desktop", "leased_at" => "2026-11-27T14:05:00Z" } } ]

    status, output = run_worker(agent_id.to_s)

    assert_equal 1, status
    assert_match(/running on runner "desktop" since 2026-11-27T14:05:00Z/, output)
  end

  test "workspace elsewhere, unknown agent and rejected secret: exit status 1 with the reason" do
    configure
    @api.lease_refusal = [ 409, { "error" => { "code" => "workspace_elsewhere", "runner" => "desktop" } } ]
    status, output = run_worker(agent_id.to_s)
    assert_equal 1, status
    assert_match(/workspace on runner "desktop"/, output)

    @api.lease_refusal = nil
    status, output = run_worker((agent_id + 1).to_s)
    assert_equal 1, status
    assert_match(/no agent #{agent_id + 1}/, output)

    @api.lease_refusal = [ 401, { "error" => { "code" => "invalid_runner_secret" } } ]
    status, output = run_worker(agent_id.to_s)
    assert_equal 1, status
    assert_match(/rejected the secret of runner "laptop".*register --url/m, output)
  end

  test "no clone: exit status 1 naming OPS, and the lease released" do
    configure
    @api.projects = [ { "id" => 3, "short_name" => "OPS" } ]

    status, output = run_worker(agent_id.to_s)

    assert_equal 1, status
    assert_match(/OPS/, output)
    assert_match(/--clone <PROJECT>=<path>/, output)
    assert_equal 1, @api.calls("DELETE", %r{/api/runner/leases/1}).size
    assert_nil @api.live_lease
  end

  test "started twice on one machine: the second ends with exit status 1, saying Fish already runs here, and the first keeps its lease" do
    configure
    first = start_worker(agent_id.to_s)
    wait_until("the first lease") { @api.live_lease }

    status, output = run_worker(agent_id.to_s)

    assert_equal 1, status
    assert_match(/Fish \(agent #{agent_id}\) already runs here/, output)
    assert_equal 1, @api.leases.size
    assert alive?(first)
    assert_equal 0, stop_worker(first)
  end

  # Waiting for a request

  test "nothing to do: takes with the run token in every project with a clone, and no Claude Code process" do
    configure(clones: { "TEST" => create_clone, "MNT" => create_clone("mnt") })
    @api.projects = [ StandInGoalner::PROJECT, { "id" => 2, "short_name" => "MNT" }, { "id" => 3, "short_name" => "OPS" } ]

    pid = start_worker(agent_id.to_s)
    wait_until("several rounds of takes") { @api.claims.size >= 6 }

    assert_equal 0, stop_worker(pid)
    claims = @api.claims
    assert_equal [ @api.leases.first["token"] ], claims.map { |claim| claim[:token] }.uniq
    assert_equal %w[/api/projects/1/requests/claim /api/projects/2/requests/claim], claims.map { |claim| claim[:path] }.uniq.sort
    assert_empty fake_calls
    output = output_of(pid)
    assert_not_includes output, StandInGoalner::SECRET
    assert_not_includes output, @api.leases.first["token"]
  end

  test "Goalner down: said once, takes go on less often, and it is said when Goalner answers again" do
    configure
    pid = start_worker(agent_id.to_s)
    wait_until("a take") { @api.claims.any? }

    @api.down = true
    down_since = @api.requests.size
    sleep 2
    attempts = @api.requests.size - down_since
    @api.down = false
    wait_until("Goalner answering again") { output_of(pid).include?("Goalner answers again") }

    assert_equal 0, stop_worker(pid)
    assert_equal 1, output_of(pid).scan("Goalner cannot be reached").size
    assert_operator attempts, :<=, 8, "a 0.2 second wait doubling up to 0.4 makes at most about 6 attempts in 2 seconds"
  end

  test "lease lapsed while asleep: the worker leases the agent again and carries on, and a second loss within the window ends it" do
    configure
    pid = start_worker(agent_id.to_s)
    wait_until("a take") { @api.claims.any? }

    @api.synchronize { @api.leases.each { |lease| lease["ended"] = true } }
    wait_until("a second lease") { @api.leases.size == 2 && @api.live_lease }
    wait_until("a take with the new run token") { @api.claims.last[:token] == @api.leases.last["token"] }
    assert alive?(pid)

    @api.synchronize { @api.leases.each { |lease| lease["ended"] = true } }
    assert_equal 1, wait_for_exit(pid)
    assert_match(/lease ended twice within 10 minutes/, output_of(pid))
  end
end
