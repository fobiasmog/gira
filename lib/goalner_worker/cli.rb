require "optparse"
require_relative "agents"
require_relative "worker"

module GoalnerWorker
  # bin/goalner-worker's command line (spec agent-worker):
  #
  #   bin/goalner-worker register --url <Goalner> [--token <runner secret>]
  #     [--workspaces <directory>] [--clone <PROJECT>=<path>]...
  #   bin/goalner-worker [<agent name or id>] [--url <Goalner>]
  class Cli
    PROJECT_FORMAT = /\A[A-Z][A-Z0-9]{1,9}\z/
    USAGE = <<~TEXT.freeze
      Usage:
        bin/goalner-worker [<agent name or id>] [--url <Goalner address>]
        bin/goalner-worker register --url <Goalner address> [--token <runner secret>]
          [--workspaces <directory>] [--clone <PROJECT>=<path>]...
    TEXT

    def initialize(argv, env: ENV, out: $stdout, err: $stderr)
      @argv = argv.dup
      @env = env
      @out = out
      @err = err
    end

    def run
      @argv.first == "register" ? register(@argv.drop(1)) : start(@argv)
      0
    rescue Error, OptionParser::ParseError => error
      @err.puts error.message
      1
    end

    private
      # Runs the agent the argument names, by id, by name or by
      # PROJECT/Name; without an argument, lists the agents the runner can
      # run (spec agent-worker, "Start an agent").
      def start(argv)
        url = nil
        OptionParser.new { |parser| parser.on("--url URL") { |value| url = value } }.parse!(argv)
        runner = Config.load(Config.default_path(@env)).choose(url)
        argument = argv.first
        return list(runner) if argument.nil? || argument.strip.empty?

        agents = Agents.fetch(runner)
        agent_id = agents.find(argument)
        Worker.new(agent_id:, name: agents.name_of(agent_id), runner:, env: @env, console: Console.new(@out)).run
      end

      def list(runner)
        agents = Agents.fetch(runner)
        if agents.empty?
          raise Error, "Runner #{runner.name.inspect} can run no agent yet. Agents are created in Goalner first, on a project's Agents screen; " \
            "then start one with: bin/goalner-worker <agent name>"
        end

        @out.puts agents.listing
      end

      # Checks the runner's secret with Goalner and saves the runner, merged
      # into what is saved for its address (spec agent-worker, "Register a
      # runner"). Nothing is written when anything is refused.
      def register(argv)
        options = { clones: {} }
        OptionParser.new do |parser|
          parser.on("--url URL") { |value| options[:url] = Config.normalize_url(value) }
          parser.on("--token SECRET") { |value| options[:token] = value }
          parser.on("--workspaces DIRECTORY") { |value| options[:workspaces] = File.expand_path(value) }
          parser.on("--clone PROJECT=PATH") { |value| add_clone(options[:clones], value) }
        end.parse!(argv)
        raise Error, "Give the Goalner address with --url.\n\n#{USAGE}" unless options[:url]

        config = Config.load(Config.default_path(@env))
        saved = config.find(options[:url])
        secret = options[:token] || saved&.secret
        raise Error, "The runner's secret is needed for a new address: pass it with --token. Goalner shows it once, when the runner is created or its secret rotated." unless secret

        profile = check_secret(options[:url], secret)
        runner = Runner.new(url: options[:url], secret:, name: profile["name"],
          workspaces: options[:workspaces] || saved&.workspaces || File.expand_path("~/goalner/workspaces"),
          clones: (saved&.clones || {}).merge(options[:clones]))
        config.put(runner)
        config.write

        @out.puts "Registered runner #{runner.name.inspect} of #{profile.dig('owner', 'name')} for #{runner.url}."
        @out.puts "Workspaces go to #{runner.workspaces}."
        if runner.clones.empty?
          @out.puts "No project has a clone yet: add one with --clone <PROJECT>=<path>."
        else
          runner.clones.sort.each { |project, path| @out.puts "  #{project}: #{path}" }
        end
        options[:clones].each do |_project, path|
          next if File.directory?(File.join(path, "openspec"))

          @out.puts "Reminder: #{path} has no openspec/ folder. Run `openspec init` there and commit it before asking for steps."
        end
      end

      def add_clone(clones, value)
        project, path = value.split("=", 2)
        raise Error, "--clone takes <PROJECT>=<path>, with the project's short name, such as TEST=~/dev/goalner." unless project&.match?(PROJECT_FORMAT) && path && !path.empty?

        expanded = File.expand_path(path)
        raise Error, "#{expanded} is not a git working copy: clone the project's repository there first." unless Git.toplevel(expanded) == Git.real(expanded)

        clones[project] = Git.real(expanded)
      end

      def check_secret(url, secret)
        response = Api.new(url).get("/api/runner", token: secret)
        raise Error, "Goalner at #{url} rejected the runner secret. Copy the command from Goalner (Settings, Runners) again, or rotate the secret there." if response.unauthorized?
        raise Error, "Goalner at #{url} answered HTTP #{response.status} when checking the runner secret." unless response.ok? && response.json.is_a?(Hash)

        response.json
      rescue Api::Unreachable => error
        raise Error, "Goalner at #{url} cannot be reached (#{error.message})."
      end
  end
end
