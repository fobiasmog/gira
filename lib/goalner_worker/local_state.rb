require "fileutils"
require "json"

module GoalnerWorker
  # The worker's small state directory, $XDG_STATE_HOME/goalner or
  # ~/.local/state/goalner (add-runners-and-workspaces design.md, decision
  # 6), with, per runner and agent:
  # - a lock file, held with flock while a worker runs the agent, so that a
  #   second one on this machine refuses to start. The operating system
  #   releases it when the worker dies;
  # - the pid of the current run, which leads its own process group, so that
  #   a worker started after one was killed stops the run it left.
  # Nothing else is kept here: the agent's work is in Goalner and in its
  # workspaces.
  class LocalState
    def initialize(env:, url:, agent_id:)
      base = env["XDG_STATE_HOME"].to_s.empty? ? File.join(Dir.home, ".local", "state") : env["XDG_STATE_HOME"]
      @directory = File.join(base, "goalner", url.sub(%r{\Ahttps?://}, "").gsub(/[^A-Za-z0-9]+/, "_"))
      @agent_id = agent_id
    end

    # Takes the agent's lock, or returns what the worker that holds it wrote.
    def lock
      FileUtils.mkdir_p(@directory, mode: 0o700)
      @lock = File.open(path("lock"), File::RDWR | File::CREAT, 0o600)
      return true if @lock.flock(File::LOCK_EX | File::LOCK_NB)

      holder = @lock.read.to_s.strip
      @lock.close
      @lock = nil
      holder.empty? ? "another worker" : holder
    end

    # What a second worker is told about this one.
    def describe(text)
      return unless @lock

      @lock.truncate(0)
      @lock.rewind
      @lock.write(text)
      @lock.flush
    end

    def unlock
      @lock&.close
      @lock = nil
    end

    def record_run(pid)
      File.write(path("run.json"), JSON.generate(pid:))
    end

    def clear_run
      FileUtils.rm_f(path("run.json"))
    end

    # The pid of a run that a killed worker left running, or nil.
    def orphaned_run
      pid = JSON.parse(File.read(path("run.json")))["pid"]
      pid if alive?(pid) && claude?(pid)
    rescue Errno::ENOENT, JSON::ParserError
      nil
    end

    private
      def path(kind) = File.join(@directory, "agent-#{@agent_id}.#{kind}")

      def alive?(pid)
        Process.kill(0, -pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      # Its leader still runs a Claude Code process, not something that got
      # the pid since.
      def claude?(pid)
        command = IO.popen([ "ps", "-o", "command=", "-p", pid.to_s ], err: File::NULL, &:read).to_s
        command.include?("claude") || command.include?(File.basename(ENV.fetch("CLAUDE_BIN", "claude")))
      end
  end
end
