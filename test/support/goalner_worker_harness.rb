require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"
require "support/stand_in_goalner"

# Runs bin/goalner-worker as people do, in a process of its own and without
# the app's bundle, against a stand-in Goalner (StandInGoalner) and a
# stand-in Claude Code (test/support/bin/claude, through CLAUDE_BIN), with
# its home, configuration, state and Claude Code directories in a temporary
# directory, and its waits shortened through the environment.
module GoalnerWorkerHarness
  WORKER = Rails.root.join("bin/goalner-worker").to_s
  FAKE_CLAUDE = Rails.root.join("test/support/bin/claude").to_s
  TIMINGS = {
    "GOALNER_WORKER_POLL_SECONDS" => "0.1", "GOALNER_WORKER_HEARTBEAT_SECONDS" => "0.3", "GOALNER_WORKER_BACKOFF_SECONDS" => "0.2",
    "GOALNER_WORKER_BACKOFF_MAX_SECONDS" => "0.4", "GOALNER_WORKER_RETRY_SECONDS" => "0.2,0.3,0.4",
    "GOALNER_WORKER_INTERRUPT_SECONDS" => "0.6", "GOALNER_WORKER_TERMINATE_SECONDS" => "0.6"
  }.freeze

  def self.included(base)
    base.setup do
      @tmp = File.realpath(Dir.mktmpdir("goalner-worker"))
      @api = StandInGoalner.new
      @api.agent = @api.agent.merge("id" => 900_000 + rand(90_000))
      @workers = []
    end

    base.teardown do
      @workers.each { |pid| stop_process(pid, "KILL") }
      fake_calls.each { |call| Process.kill("KILL", -call["pgid"]) rescue nil } if File.directory?(File.join(@tmp, "fake"))
      @api.stop
      FileUtils.rm_rf(@tmp)
      FileUtils.rm_rf(Rails.root.join("log/agents", @api.agent["id"].to_s))
    end
  end

  def home = File.join(@tmp, "home")
  def config_path = File.join(@tmp, "config", "goalner", "runners.yml")
  def workspaces_root = File.join(home, "goalner", "workspaces")
  def agent_id = @api.agent["id"]

  def worker_env(extra = {})
    { "HOME" => home, "XDG_CONFIG_HOME" => File.join(@tmp, "config"), "XDG_STATE_HOME" => File.join(@tmp, "state"),
      "CLAUDE_CONFIG_DIR" => File.join(@tmp, "claude"), "CLAUDE_BIN" => FAKE_CLAUDE, "FAKE_CLAUDE_DIR" => File.join(@tmp, "fake"),
      "GIT_AUTHOR_NAME" => "Test", "GIT_AUTHOR_EMAIL" => "test@example.com", "GIT_COMMITTER_NAME" => "Test", "GIT_COMMITTER_EMAIL" => "test@example.com",
      **TIMINGS }.merge(extra)
  end

  # A clone of a project's repository with a first commit on main, and
  # openspec/ unless told otherwise.
  def create_clone(name = "clone", openspec: true, files: {})
    path = File.join(@tmp, name)
    FileUtils.mkdir_p(path)
    git(path, "init", "-q", "-b", "main")
    File.write(File.join(path, "README.md"), "# #{name}\n")
    FileUtils.mkdir_p(File.join(path, "openspec")) && File.write(File.join(path, "openspec", "project.md"), "x\n") if openspec
    files.each do |relative, (content, mode)|
      FileUtils.mkdir_p(File.dirname(File.join(path, relative)))
      File.write(File.join(path, relative), content)
      File.chmod(mode, File.join(path, relative)) if mode
    end
    git(path, "add", ".")
    git(path, "commit", "-q", "-m", "First")
    path
  end

  def git(directory, *args)
    output, status = Open3.capture2e(worker_env.slice("HOME", *worker_env.keys.grep(/\AGIT_/)), "git", "-C", directory, *args)
    assert status.success?, "git #{args.join(' ')}: #{output}"
    output
  end

  # A configuration with one runner for the stand-in, its clones as given.
  def configure(clones: nil, url: @api.url, runners: nil)
    runners ||= [ { "url" => url, "secret" => StandInGoalner::SECRET, "name" => "laptop", "workspaces" => workspaces_root,
      "clones" => clones || { "TEST" => (@clone ||= create_clone) } } ]
    FileUtils.mkdir_p(File.dirname(config_path), mode: 0o700)
    File.write(config_path, YAML.dump(JSON.parse(JSON.generate({ "runners" => runners }))))
    File.chmod(0o600, config_path)
  end

  # Runs the worker to its end: [exit status, output].
  def run_worker(*args, env: {})
    output, status = Bundler.with_unbundled_env { Open3.capture2e(worker_env(env), WORKER, *args) }
    [ status.exitstatus, output ]
  end

  # Starts the worker in the background; its output goes to a file.
  def start_worker(*args, env: {})
    log = File.join(@tmp, "worker-#{@workers.size}.log")
    pid = Bundler.with_unbundled_env { Process.spawn(worker_env(env), WORKER, *args, out: log, err: [ :child, :out ]) }
    @workers << pid
    @logs = (@logs || {}).merge(pid => log)
    pid
  end

  def output_of(pid) = File.read(@logs.fetch(pid))

  # Sends signal and waits for the worker's exit status.
  def stop_worker(pid, signal = "INT", timeout: 10)
    Process.kill(signal, pid)
    wait_for_exit(pid, timeout:)
  end

  def wait_for_exit(pid, timeout: 10)
    deadline = Time.now + timeout
    loop do
      done, status = Process.waitpid2(pid, Process::WNOHANG)
      if done
        @workers.delete(pid)
        return status.exitstatus
      end
      flunk "the worker did not end within #{timeout} seconds:\n#{output_of(pid)}" if Time.now > deadline
      sleep 0.05
    end
  end

  def stop_process(pid, signal)
    Process.kill(signal, pid)
    Process.waitpid(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  def wait_until(message = "condition", timeout: 10)
    deadline = Time.now + timeout
    until yield
      flunk "timed out waiting for #{message}" + (@workers.any? ? ":\n#{@workers.map { |pid| output_of(pid) }.join("\n---\n")}" : "") if Time.now > deadline
      sleep 0.05
    end
  end

  def modes(*list)
    FileUtils.mkdir_p(File.join(@tmp, "fake"))
    File.write(File.join(@tmp, "fake", "modes"), list.join("\n") + "\n")
  end

  # The stand-in Claude Code's calls so far.
  def fake_calls
    path = File.join(@tmp, "fake", "calls.jsonl")
    File.exist?(path) ? File.readlines(path).map { |line| JSON.parse(line) } : []
  end

  def option(call, name) = (position = call["args"].index(name)) && call["args"][position + 1]

  def prompt_of(call) = option(call, "-p")

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def give_request(id = 12, **options)
    @api.synchronize { @api.waiting << StandInGoalner.request(id, **options) }
  end
end
