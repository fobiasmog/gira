require "test_helper"
require "support/goalner_worker_harness"

# Starting bin/goalner-worker by an agent's name or id, listing the agents,
# and waiting for requests (spec agent-worker, "Start an agent", "Waiting
# for a request" and "Configuration file safety"; add-runners-and-workspaces
# design.md, decisions 5 and 6).
class GoalnerWorkerStartTest < ActiveSupport::TestCase
  include GoalnerWorkerHarness

  # Start an agent by its id

  def listed(id, name, projects, lease: nil) = { "id" => id, "name" => name, "projects" => projects, "lease" => lease }

  test "no argument: the agents the runner can run, with their projects, where each runs and its start command, and nothing leased" do
    configure
    @api.agent_list = [ listed(agent_id, "Fish", %w[TEST]),
      listed(agent_id + 1, "Heron", %w[TEST], lease: { "runner" => { "name" => "laptop" }, "this_runner" => true, "since" => "2026-11-27T14:05:00Z" }),
      listed(agent_id + 2, "Code Reviewer", %w[OPS], lease: { "runner" => { "name" => "desktop" }, "this_runner" => false, "since" => "2026-11-27T14:05:00Z" }) ]

    status, output = run_worker

    assert_equal 0, status, output
    assert_match(/Agents that runner "laptop" can run \(#{Regexp.escape(@api.url)}\):/, output)
    assert_match(/^  Fish +TEST +not running +bin\/goalner-worker Fish$/, output)
    assert_match(/^  Heron +TEST +runs here since 2026-11-27 \d\d:\d\d +bin\/goalner-worker Heron$/, output)
    assert_match(/^  Code Reviewer +OPS \(no clone here\) +runs on desktop since .+ +bin\/goalner-worker Code\\ Reviewer$/, output)
    assert_empty @api.calls("POST", /lease/)
  end

  test "no agents yet: exit status 1, saying to create agents in Goalner first" do
    configure
    @api.agent_list = []

    status, output = run_worker

    assert_equal 1, status
    assert_match(/Agents are created in Goalner first, on a project's Agents screen/, output)
  end

  test "by name, in any letter case, or by PROJECT/Name: the worker leases that agent" do
    configure
    [ "fish", "FISH", "test/Fish" ].each do |argument|
      pid = start_worker(argument)
      wait_until("the lease for #{argument}") { output_of(pid).include?("Leased Fish (agent #{agent_id})") }
      assert_equal 0, stop_worker(pid)
    end
    assert_equal [ "/api/runner/agents/#{agent_id}/lease" ], @api.calls("POST", /lease/).map { |call| call[:path] }.uniq
  end

  test "shared name: exit status 1, listing the argument that names each, and nothing leased" do
    configure(clones: { "TEST" => create_clone, "OPS" => create_clone("ops") })
    @api.agent_list = [ listed(agent_id, "Fish", %w[TEST]), listed(agent_id + 1, "Fish", %w[OPS]) ]

    status, output = run_worker("Fish")

    assert_equal 1, status
    assert_match(/Several agents are named "Fish"/, output)
    assert_includes output, "bin/goalner-worker TEST/Fish"
    assert_includes output, "bin/goalner-worker OPS/Fish"
    assert_empty @api.calls("POST", /lease/)
  end

  test "a shared name picks the one agent of a project with a clone here" do
    configure
    @api.agent_list = [ listed(agent_id, "Fish", %w[TEST]), listed(agent_id + 1, "Fish", %w[OPS]) ]

    pid = start_worker("Fish")
    wait_until("a lease") { @api.live_lease }

    assert_equal 0, stop_worker(pid)
    assert_equal [ "/api/runner/agents/#{agent_id}/lease" ], @api.calls("POST", /lease/).map { |call| call[:path] }
  end

  test "unknown name: exit status 1, naming it and listing the agents the runner can run" do
    configure

    status, output = run_worker("Owl")

    assert_equal 1, status
    assert_match(/can run no agent named "Owl"/, output)
    assert_match(/^  Fish +TEST +not running +bin\/goalner-worker Fish$/, output)
    assert_empty @api.calls("POST", /lease/)
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
    assert_match(/Fish is running on runner "desktop" since 2026-11-27T14:05:00Z/, output)
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
