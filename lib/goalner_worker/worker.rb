require "json"
require "open3"
require "fileutils"
require_relative "agents"
require_relative "api"
require_relative "child"
require_relative "config"
require_relative "console"
require_relative "git"
require_relative "local_state"

module GoalnerWorker
  # The checkout bin/goalner-worker runs from: its instructions, settings
  # and MCP configuration come from here, and its logs go here.
  HOME = File.expand_path("../..", __dir__)

  # How long the worker waits for each thing, in seconds. Tests shorten them
  # through the environment.
  Timings = Struct.new(:poll, :heartbeat, :backoff, :backoff_max, :retries, :interrupt, :terminate, :relapse, keyword_init: true) do
    def self.from(env)
      seconds = ->(name, default) { Float(env.fetch("GOALNER_WORKER_#{name}_SECONDS", default)) }
      new(poll: seconds.("POLL", 10), heartbeat: seconds.("HEARTBEAT", 30), backoff: seconds.("BACKOFF", 10), backoff_max: seconds.("BACKOFF_MAX", 60),
        retries: env.fetch("GOALNER_WORKER_RETRY_SECONDS", "60,300,900").split(",").map { |value| Float(value) },
        interrupt: seconds.("INTERRUPT", 30), terminate: seconds.("TERMINATE", 10), relapse: seconds.("RELEASE", 600))
    end
  end

  # Runs one agent through one runner (spec agent-worker;
  # add-runners-and-workspaces design.md, decisions 5 and 6). It leases the
  # agent, waits for requests without running Claude Code, attaches to the
  # workspace of each request's change, runs the request as one headless
  # `claude -p` in the session of the agent's stint, and continues the same
  # request in the same session after any interruption. It holds no identity
  # and no state of its own: Goalner and the workspace hold everything.
  #
  # A single thread: each run's output is read with a one-second timeout,
  # which gives the worker a turn every second for heartbeats, waits and
  # signals.
  class Worker
    NOTES = {
      interrupted: "Your previous run of this request was interrupted before it finished. Check the workspace (`git status`, `git log`) " \
        "and carry on from where it stopped; do not start over.",
      files_lost: "The workspace's files were lost: its worktree was created again from the change's branch, so anything that was " \
        "not committed is gone. Check what is missing before you go on.",
      context_lost: "Your earlier conversation on this change was lost. Read the change (`showChange`), its thread " \
        "(`listChangeComments`) and the branch's commits to catch up before you go on."
    }.freeze
    QUOTE = 2_000

    # Raised to leave whatever the worker is doing when it is told to stop.
    class Stopping < StandardError; end

    # name: the agent's, when it is known before leasing, for messages.
    # url_option: the address to name in commands the worker shows, when
    # several runners are registered.
    def initialize(agent_id:, runner:, name: nil, url_option: nil, env: ENV, console: Console.new, home: HOME)
      @agent_id = agent_id
      @label = name || "Agent #{agent_id}"
      @url_option = url_option
      @runner = runner
      @env = env
      @console = console
      @home = home
      @api = Api.new(runner.url)
      @timings = Timings.from(env)
      @state = LocalState.new(env:, url: runner.url, agent_id:)
      @lost_leases = []
    end

    def run
      take_lock
      stop_orphaned_run
      lease!
      trap_signals
      remove_finished_workspaces
      resume_taken_request
      wait_for_requests
    rescue Stopping
      nil
    ensure
      release
      @state.unlock
    end

    private
      # Starting

      def take_lock
        holder = @state.lock
        return if holder == true

        raise Error, "#{holder} already runs here through #{@runner.url}. Stop it first, or start another agent."
      end

      def stop_orphaned_run
        pid = @state.orphaned_run or return @state.clear_run

        @console.event("A run left by a worker that was killed is still going (pid #{pid}); stopping it first")
        orphan = OrphanRun.new(pid)
        [ [ "INT", @timings.interrupt ], [ "TERM", @timings.terminate ], [ "KILL", 5 ] ].each do |signal, grace|
          break unless orphan.alive?

          orphan.signal(signal)
          orphan.wait(grace)
        end
        @state.clear_run
      end

      # Leases the agent (spec agent-runners, "Lease an agent"), and keeps
      # what the lease names. Every refusal ends the worker with its reason.
      def lease!
        response = @api.post("/api/runner/agents/#{@agent_id}/lease", token: @runner.secret)
        refuse_lease(response) unless response.status == 201

        @lease = response.json
        @agent = @lease.fetch("agent")
        @token = @lease.dig("lease", "run_token")
        @projects = @lease.fetch("projects").select { |project| @runner.clones.key?(project["short_name"]) }
        @state.describe("#{@agent['name']} (agent #{@agent_id})")
        if @projects.empty?
          names = @lease.fetch("projects").map { |project| project["short_name"] }
          release
          raise Error, Agents.no_clone_help(@agent["name"], names, url: @url_option)
        end
        @console.event("Leased #{@agent['name']} (agent #{@agent_id}) to runner #{@runner.name.inspect}; projects #{@projects.map { |project| project['short_name'] }.join(', ')}")
        @lease
      rescue Api::Unreachable => error
        raise Error, "Goalner at #{@runner.url} cannot be reached (#{error.message})."
      end

      def refuse_lease(response)
        error = response.json.is_a?(Hash) ? response.json["error"].to_h : {}
        raise Error, case [ response.status, error["code"] ]
        in [ 401, _ ] then "Goalner rejected the secret of runner #{@runner.name.inspect}: it was rotated or revoked. " \
          "Register again with its current secret: bin/goalner-worker register --url #{@runner.url} --token <secret>"
        in [ 404, _ ] then "Goalner has no agent #{@agent_id} that this runner's owner can see. " \
          "Run bin/goalner-worker without an argument to list the agents it can run."
        in [ 409, "agent_leased" ] then "#{@label} is running on runner #{error['runner'].inspect} since #{error['leased_at']}. Stop that worker first."
        in [ 409, "workspace_elsewhere" ] then "#{@label}'s change has its workspace on runner #{error['runner'].inspect}: start the agent there."
        in [ 429, _ ] then "Goalner refused the lease: this runner leased too often. Try again later."
        else "Goalner refused the lease with HTTP #{response.status}."
        end
      end

      # Leases the agent again after its run token was refused, at most once
      # in the release window (spec agent-worker, "Waiting for a request").
      def lease_again!(reason)
        now = monotonic
        @lost_leases.reject! { |time| time < now - @timings.relapse }
        if @lost_leases.any?
          raise Error, "#{@agent['name']}'s lease ended twice within #{(@timings.relapse / 60).round} minutes (#{reason}). " \
            "Another worker may be using this runner's secret: register each machine as its own runner."
        end

        @lost_leases << now
        @console.event("#{@agent['name']}'s lease ended (#{reason}); leasing it again")
        lease!
      end

      def release
        return unless @lease

        lease, @lease = @lease, nil
        @api.delete("/api/runner/leases/#{lease.dig('lease', 'id')}", token: @runner.secret)
        @console.event("Released #{@agent['name']}")
      rescue Api::Unreachable
        @console.event("Could not release #{@agent['name']}: Goalner cannot be reached. Its lease lapses on its own.")
      end

      def trap_signals
        %w[INT TERM].each { |signal| Signal.trap(signal) { @stop_signal = signal } }
      end

      def stopping? = !@stop_signal.nil?

      # The request the lease names, taken before this worker started: it
      # continues in the same session (spec agent-worker, "Stop and restart
      # the worker").
      def resume_taken_request
        change = @lease["change"] or return
        request = change["request"] or return
        project = @projects.find { |each| each["id"] == change.dig("project", "id") }
        return @console.event("#{@agent['name']}'s request #{request['id']} is in project #{change.dig('project', 'short_name')}, which has no clone here") unless project

        merged = request.merge("change" => request["change"].merge(change.slice("base_branch", "session_id", "workspace")))
        work(merged, project, [ :interrupted ])
      end

      # Waiting

      # A round of takes every poll interval, in every project with a clone,
      # backing off while Goalner is down (spec agent-worker, "Waiting for a
      # request").
      def wait_for_requests
        @console.event("Waiting for requests")
        loop do
          raise Stopping if stopping?

          outcome = take_round
          case outcome.first
          when :request then work(outcome[1], outcome[2])
          when :unauthorized then lease_again!("its run token was refused")
          when :down then pause(backoff(outcome[1]))
          else
            recovered
            pause(@timings.poll)
          end
        end
      end

      def take_round
        @projects.each do |project|
          outcome = take(project)
          return outcome + [ project ] if outcome.first == :request
          return outcome unless outcome.first == :none
        end
        [ :none ]
      end

      # One take with the run token: [:request, request], [:none],
      # [:unauthorized], or [:down, why] when Goalner cannot answer.
      def take(project)
        response = @api.post("/api/projects/#{project['id']}/requests/claim", token: @token)
        return [ :unauthorized ] if response.unauthorized?
        return [ :down, "it answered HTTP #{response.status}" ] if response.server_error? || !response.ok?

        recovered
        request = response.json&.fetch("request", nil)
        request ? [ :request, request ] : [ :none ]
      rescue Api::Unreachable => error
        [ :down, error.message ]
      end

      def backoff(why)
        @console.event("Goalner cannot be reached (#{why}); trying again") if @down_since.nil?
        @down_since ||= monotonic
        @backoff = @backoff ? [ @backoff * 2, @timings.backoff_max ].min : @timings.backoff
      end

      def recovered
        return unless @down_since

        @console.event("Goalner answers again")
        @down_since = @backoff = nil
      end

      # Working on a request

      # Works on request until it is done, failed, cancelled or handed on
      # (spec agent-worker, "Run a request", "Heartbeat and stopping a run"
      # and "After a run").
      def work(request, project, notes = [])
        unfinished = 0
        loop do
          workspace = attach(request, project, notes) or return
          outcome = run_request(request, project, workspace, notes)
          checkpoint(workspace)
          case outcome.first
          when :none then return
          when :other then request, notes, unfinished = outcome[1], [], 0
          when :lease_lost then notes = [ :interrupted ]
          when :ended
            after = after_run(request, project, unfinished + 1) or return
            request, notes = after[:request], after[:notes]
            unfinished = after[:same] ? unfinished + 1 : 0
          end
        end
      end

      # What follows a run that ended on its own: nil when its request is no
      # longer the agent's, or the request to run next and its notes.
      def after_run(request, project, unfinished)
        outcome = take_until_answered(project)
        case outcome.first
        when :none
          remove_finished_workspaces if request["kind"] == "archive"
          nil
        when :request
          next_request = outcome[1]
          if next_request["id"] != request["id"]
            remove_finished_workspaces if request["kind"] == "archive"
            return { request: next_request, notes: [], same: false }
          end
          if unfinished > @timings.retries.size
            fail_request(request, project, "The worker ran this request #{unfinished} times, and each run ended without finishing it. " \
              "The last run reported:\n\n```\n#{@last_report.to_s[-QUOTE..] || @last_report}\n```")
            return
          end

          wait = @timings.retries[unfinished - 1]
          @console.event("The run ended without finishing request #{request['id']}; continuing it in #{wait.round} seconds")
          retry_wait(request, project, wait)
        end
      end

      # Waits before continuing request, taking requests as the heartbeat.
      def retry_wait(request, project, seconds)
        deadline = monotonic + seconds
        while monotonic < deadline
          pause([ @timings.heartbeat, deadline - monotonic ].min)
          outcome = take(project)
          case outcome.first
          when :none then return nil
          when :request then return { request: outcome[1], notes: [], same: false } if outcome[1]["id"] != request["id"]
          when :unauthorized then lease_again!("its run token was refused")
          end
        end
        { request:, notes: [ :interrupted ], same: true }
      end

      # A take that waits out a Goalner that cannot be reached, and leases
      # again after a refused run token.
      def take_until_answered(project)
        loop do
          outcome = take(project)
          case outcome.first
          when :down then pause(backoff(outcome[1]))
          when :unauthorized then lease_again!("its run token was refused")
          else return outcome
          end
        end
      end

      def fail_request(request, project, comment)
        @console.event("Finishing request #{request['id']} as failed: #{comment.lines.first.strip}")
        response = @api.post("/api/projects/#{project['id']}/requests/#{request['id']}/finish", token: @token,
          body: { outcome: "failed", comment: })
        @console.event("Goalner did not take the failure (HTTP #{response.status})") unless response.ok?
        nil
      rescue Api::Unreachable => error
        @console.event("Could not finish request #{request['id']}: #{error.message}")
        nil
      end

      # Attaching

      # Settles the workspace of request's change (spec agent-worker, "Attach
      # to a workspace") and runs the attach hook. Returns the workspace, or
      # nil when the request was finished as failed or cannot go on now.
      def attach(request, project, notes)
        change = request.fetch("change")
        clone = File.expand_path(@runner.clones.fetch(project["short_name"]))
        workspace = change["workspace"]
        workspace = nil unless workspace && workspace["state"] == "active"
        failure = workspace ? reuse(clone, workspace, notes) : create(clone, project, change)
        return fail_request(request, project, failure) if failure.is_a?(String)

        workspace ||= record(request, project, change, failure)
        return unless workspace

        hook_failure = run_hook(workspace["path"], "goalner-attach", change)
        return fail_request(request, project, "The attach hook `bin/goalner-attach` failed:\n\n```\n#{hook_failure}\n```") if hook_failure

        workspace
      end

      # Creates the worktree of a change with no workspace, or finds the one
      # a killed worker created. Returns {path:, branch:}, or why it cannot.
      def create(clone, project, change)
        path = File.join(File.expand_path(@runner.workspaces), project["short_name"], change["name"])
        branch = change["name"]
        base = change.fetch("base_branch")
        if Git.branch?(clone, branch)
          return { path:, branch: } if Git.worktree_of?(clone, path, branch)

          return "The branch `#{branch}` already exists in #{clone}, and #{path} holds no worktree of it, so it may be someone " \
            "else's work. Rename the change or delete the branch, then ask for the step again."
        end
        return "#{path} exists, and it is no worktree of the branch `#{branch}`. Move it away, then ask for the step again." if File.exist?(path)
        return "The base branch `#{base}` does not exist in #{clone}." unless Git.commit?(clone, base)

        FileUtils.mkdir_p(File.dirname(path))
        output, ok = Git.run(clone, "worktree", "add", "-b", branch, path, base)
        return "Creating the worktree failed:\n\n```\n#{output.strip}\n```" unless ok

        @console.event("Created the workspace of #{change['name']} at #{path}, on the new branch #{branch} from #{base}")
        { path:, branch: }
      end

      # Uses an active workspace, creating its worktree again when its files
      # are gone. Returns nil, or why it cannot.
      def reuse(clone, workspace, notes)
        path = workspace["path"]
        branch = workspace["branch"]
        return "The branch `#{branch}` of this change's workspace no longer exists in #{clone}." unless Git.branch?(clone, branch)

        if File.exist?(path)
          return "#{path} is no worktree of the branch `#{branch}`." unless Git.worktree_of?(clone, path, branch)

          return
        end

        Git.run(clone, "worktree", "prune")
        FileUtils.mkdir_p(File.dirname(path))
        output, ok = Git.run(clone, "worktree", "add", path, branch)
        return "Creating the worktree again failed:\n\n```\n#{output.strip}\n```" unless ok

        @console.event("The workspace's files were gone; created the worktree again at #{path}")
        notes << :files_lost unless notes.include?(:files_lost)
        nil
      end

      def record(request, project, change, created)
        response = @api.put("/api/runner/changes/#{change['id']}/workspace", token: @runner.secret, body: created)
        return response.json if response.ok?

        if response.status == 422
          return fail_request(request, project, "Goalner refused to record the workspace at #{created[:path]}: #{response.body}")
        end

        @console.event("Goalner did not record the workspace of #{change['name']} (HTTP #{response.status}); trying again later")
        nil
      rescue Api::Unreachable => error
        @console.event("Could not record the workspace of #{change['name']}: #{error.message}")
        nil
      end

      # Runs bin/<name> of the workspace when it is there and executable,
      # with the run's environment. Returns the end of its output when it
      # fails, or nil.
      def run_hook(path, name, change)
        hook = File.join(path, "bin", name)
        return unless File.file?(hook) && File.executable?(hook)

        @console.event("Running bin/#{name} in #{path}")
        child = Child.new([ hook ], env: run_env(change), chdir: path, on_line: ->(line) { @console.event("  #{line.chomp}") }).start
        while child.pump(1)
          stop_child(child) && raise(Stopping) if stopping?
        end
        child.finish
        child.success? ? nil : child.tail
      end

      # Running

      def run_request(request, project, workspace, notes)
        change = request.fetch("change")
        session = change.fetch("session_id")
        resuming = transcript?(session)
        notes += [ :context_lost ] if !resuming && earlier_requests_in_stint?(project, change)
        command = claude_command(request, project, session, resuming:, notes:)
        log = File.join(@home, "log", "agents", @agent_id.to_s, "#{request['id']}.jsonl")
        @console.event("#{resuming ? 'Continuing' : 'Starting'} session #{session} for the #{request['kind']} request #{request['id']} " \
          "of #{change['name']} in #{workspace['path']}")
        child = Child.new(command, env: run_env(change), chdir: workspace["path"], log:, on_line: ->(line) { watch(line) }).start
        @state.record_run(child.pid)
        @last_report = nil
        watch_run(child, request, project)
      ensure
        @state.clear_run
      end

      # Pumps the run's output every second, and takes a request every
      # heartbeat interval while it runs, and at once after the run reports
      # a compaction: a blocked compaction does not stop the run, so the take
      # that finds its change blocked has to come before the run goes on to
      # finish its request.
      def watch_run(child, request, project)
        next_beat = monotonic + @timings.heartbeat
        @take_now = false
        while child.pump([ 1, @timings.heartbeat ].min)
          if stopping?
            stop_child(child)
            raise Stopping
          end
          next if monotonic < next_beat && !@take_now

          @take_now = false
          next_beat = monotonic + @timings.heartbeat
          outcome = take(project)
          case outcome.first
          when :none
            @console.event("Request #{request['id']} is no longer #{@agent['name']}'s: it was cancelled, the agent was released, or its change is blocked. Stopping the run")
            stop_child(child)
            return [ :none ]
          when :request
            next if outcome[1]["id"] == request["id"]

            @console.event("Goalner hands #{@agent['name']} request #{outcome[1]['id']} instead. Stopping the run")
            stop_child(child)
            return [ :other, outcome[1] ]
          when :unauthorized
            stop_child(child)
            lease_again!("its run token was refused during a run")
            return [ :lease_lost ]
          end
        end
        child.finish
        @last_report ||= child.tail
        [ :ended ]
      end

      def stop_child(child)
        @console.event("Stopping the run")
        child.stop(interrupt_grace: @timings.interrupt, terminate_grace: @timings.terminate)
        @last_report ||= child.tail
        true
      end

      # Shows a line of the run's output, and keeps what its result says. A
      # status line (compacting, and done compacting) asks for a take at once.
      def watch(line)
        @console.run_line(line)
        message = JSON.parse(line)
        @last_report = [ message["subtype"], message["result"] ].compact.join(": ") if message["type"] == "result"
        @take_now = true if message["type"] == "system" && message["subtype"] == "status"
      rescue JSON::ParserError
        nil
      end

      def claude_command(request, project, session, resuming:, notes:)
        [ @env.fetch("CLAUDE_BIN", "claude"), "-p", prompt(request, project, first: !resuming, notes:),
          (resuming ? "--resume" : "--session-id"), session,
          "--settings", File.join(@home, ".claude", "goalner-worker.settings.json"),
          "--strict-mcp-config", "--mcp-config", File.join(@home, ".claude", "goalner-worker.mcp.json"),
          "--output-format", "stream-json", "--verbose",
          *([ "--model", @agent["model"] ] if @agent["model"]),
          *([ "--append-system-prompt", @agent["instructions"] ] if @agent["instructions"]) ]
      end

      # The request as JSON, after the worker's instructions on a session's
      # first run, and with the notes at the end.
      def prompt(request, project, first:, notes:)
        parts = []
        parts << File.read(File.join(__dir__, "instructions.md")) if first
        parts << "## Your request\n\nYou are #{@agent['name']} (user id #{@agent['id']}). The worker took this request for you " \
          "in project #{project['short_name']} (id #{project['id']}). Do its step, then finish it with `finishRequest`.\n\n" \
          "```json\n#{JSON.pretty_generate(request.merge('project' => project))}\n```"
        parts << "## Notes\n\n#{notes.uniq.map { |note| "- #{NOTES.fetch(note)}" }.join("\n")}" if notes.any?
        parts.join("\n\n")
      end

      def run_env(change)
        { "GOALNER_TOKEN" => @token, "GOALNER_URL" => @runner.url, "GOALNER_MCP_URL" => @lease["mcp_url"],
          "GOALNER_WORKER_HOME" => @home, "GOALNER_TEST_DB_SUFFIX" => "c#{change['id']}" }
      end

      # Whether Claude Code keeps a transcript of the session, under any
      # working directory: session ids are UUIDs, so the name is enough.
      def transcript?(session)
        claude_home = @env["CLAUDE_CONFIG_DIR"].to_s.empty? ? File.join(Dir.home, ".claude") : @env["CLAUDE_CONFIG_DIR"]
        Dir.glob(File.join(claude_home, "projects", "*", "#{session}.jsonl")).any?
      end

      # Whether the agent took another request of change in this stint
      # before: then a missing transcript means a lost context.
      def earlier_requests_in_stint?(project, change)
        response = @api.get("/api/projects/#{project['id']}/changes/#{change['id']}", token: @token)
        return false unless response.ok?

        since = response.json.dig("agent", "since") or return false
        response.json.fetch("history", []).count do |entry|
          entry["kind"] == "request" && entry["state"] == "taken" && entry.dig("actor", "id") == @agent["id"] && entry["created_at"] >= since
        end > 1
      rescue Api::Unreachable
        false
      end

      # After a run: the commit the branch is at, and whether files are
      # uncommitted (spec agent-workspaces, "Checkpoints").
      def checkpoint(workspace)
        head = Git.head(workspace["path"]) or return
        @api.patch("/api/runner/workspaces/#{workspace['id']}", token: @runner.secret,
          body: { head_commit: head, uncommitted: Git.uncommitted?(workspace["path"]) })
      rescue Api::Unreachable => error
        @console.event("Could not report a checkpoint: #{error.message}")
      end

      # Removing workspaces

      # The runner's workspaces of archived changes (spec agent-worker,
      # "Remove finished workspaces"): each is removed without forcing after
      # the detach hook, or kept while it holds uncommitted changes. The
      # branch stays.
      def remove_finished_workspaces
        response = @api.get("/api/runner/workspaces", token: @runner.secret, query: { to_remove: "true" })
        return unless response.ok?

        response.json.each do |workspace|
          state = removal(workspace) or next
          @api.patch("/api/runner/workspaces/#{workspace['id']}", token: @runner.secret, body: { state: })
        end
      rescue Api::Unreachable => error
        @console.event("Could not list the workspaces to remove: #{error.message}")
      end

      def removal(workspace)
        path = workspace["path"]
        return "removed" unless File.exist?(path)

        if Git.uncommitted?(path)
          @console.event("Keeping the workspace of #{workspace.dig('change', 'name')} at #{path}: it holds uncommitted changes")
          return "kept"
        end
        main = Git.main_worktree(path)
        if (failure = run_hook(path, "goalner-detach", workspace.fetch("change")))
          @console.event("bin/goalner-detach failed in #{path}; the workspace stays for now:\n#{failure}")
          return
        end
        output, ok = Git.run(main, "worktree", "remove", path)
        if ok
          @console.event("Removed the workspace of #{workspace.dig('change', 'name')} at #{path}; its branch stays")
          "removed"
        else
          @console.event("Keeping the workspace at #{path}: #{output.strip}")
          "kept"
        end
      end

      # Waits up to seconds, a little at a time, leaving at once when told
      # to stop.
      def pause(seconds)
        deadline = monotonic + seconds
        while (left = deadline - monotonic).positive?
          raise Stopping if stopping?

          sleep [ left, 0.2 ].min
        end
        raise Stopping if stopping?
      end

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # A run that a killed worker left: not this worker's child, so it is
  # watched by signals alone.
  class OrphanRun
    def initialize(pid)
      @pid = pid
    end

    def alive?
      Process.kill(0, -@pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    def signal(name)
      Process.kill(name, -@pid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end

    def wait(seconds)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      sleep 0.1 while alive? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    end
  end
end
