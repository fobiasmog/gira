require "time"
require_relative "api"
require_relative "config"

module GoalnerWorker
  # A word as a shell reads it: as it is when it holds nothing the shell
  # treats specially, otherwise in single quotes. The Agents screen quotes
  # the same way.
  def self.shell_word(word)
    word = word.to_s
    word.match?(%r{\A[A-Za-z0-9_./:@%+=,-]+\z}) ? word : "'#{word.gsub("'") { %q('\'') }}'"
  end

  # The agents a runner can run (spec agent-runners, "Agents a runner can
  # run"), as Goalner lists them, and finding one by what a person types
  # (spec agent-worker, "Start an agent"): its id, its name in any letter
  # case, or PROJECT/Name.
  class Agents
    PROJECT_FORMAT = /\A[A-Z][A-Z0-9]{1,9}\z/i

    def self.fetch(runner)
      response = Api.new(runner.url).get("/api/runner/agents", token: runner.secret)
      if response.unauthorized?
        raise Error, "Goalner rejected the secret of runner #{runner.name.inspect}: it was rotated or revoked. " \
          "Register again with its current secret: bin/goalner-worker register --url #{runner.url} --token <secret>"
      end
      raise Error, "Goalner at #{runner.url} answered HTTP #{response.status} when asked for the runner's agents." unless response.ok?

      new(runner, response.json)
    rescue Api::Unreachable => error
      raise Error, "Goalner at #{runner.url} cannot be reached (#{error.message})."
    end

    def initialize(runner, list)
      @runner = runner
      @list = list
    end

    def empty? = @list.empty?

    # The name of the agent with id, or nil when the runner cannot run it.
    def name_of(id) = @list.find { |agent| agent["id"] == id }&.fetch("name")

    # The projects of the agent with id when none of them has a clone on
    # this machine, or nil: when it has one, or the runner cannot tell.
    def uncloned_projects(id)
      agent = @list.find { |each| each["id"] == id }
      agent["projects"] if agent && !cloned?(agent)
    end

    # What to do when no project of agent name has a clone here: register a
    # clone of one of them, then start the agent again. url: the address to
    # name in the commands, when several runners are registered.
    def self.no_clone_help(name, projects, url: nil)
      address = url ? " --url #{GoalnerWorker.shell_word(url)}" : ""
      registered = projects.empty? ? "it belongs to no project that this runner's owner shares" : "it works in #{projects.join(', ')}, and none of them has a clone registered on this machine"
      lines = [ "#{name || 'This agent'} cannot run here: #{registered}." ]
      if projects.any?
        lines << "Clone the project's repository, register the clone, then start #{name || 'the agent'} again:"
        lines << ""
        projects.each { |project| lines << "  bin/goalner-worker register#{address} --clone #{project}=<path to the clone>" }
        lines << "  bin/goalner-worker#{address} #{GoalnerWorker.shell_word(name)}" if name
      end
      lines.join("\n")
    end

    # The id of the agent argument names, or an Error that says why there
    # is none, listing what to type instead.
    def find(argument)
      return Integer(argument, 10) if argument.match?(/\A\d+\z/)

      matches = matching(argument)
      if matches.size > 1
        cloned = matches.select { |agent| cloned?(agent) }
        matches = cloned if cloned.one?
      end
      return matches.first["id"] if matches.one?

      if matches.empty?
        raise Error, "Runner #{@runner.name.inspect} can run no agent named #{argument.inspect}.\n\n#{listing}"
      end
      raise Error, "Several agents are named #{argument.inspect}. Start one of them with:\n" +
        matches.map { |agent| "  #{command(agent)}" }.join("\n")
    end

    # Each agent with its projects, where it runs now, and its start command.
    def listing
      return "Runner #{@runner.name.inspect} can run no agent yet." if @list.empty?

      rows = @list.map { |agent| [ agent["name"], projects(agent), whereabouts(agent), command(agent) ] }
      widths = rows.transpose.map { |column| column.map(&:length).max }
      "Agents that runner #{@runner.name.inspect} can run (#{@runner.url}):\n" +
        rows.map { |row| "  " + row.each_with_index.map { |cell, index| index == row.size - 1 ? cell : cell.ljust(widths[index]) }.join("  ") }.join("\n")
    end

    # The shortest argument that names agent alone: its name, PROJECT/Name,
    # or its id.
    def command(agent)
      argument = [ agent["name"], *agent["projects"].map { |project| "#{project}/#{agent['name']}" } ]
        .find { |candidate| matching(candidate).map { |each| each["id"] } == [ agent["id"] ] } || agent["id"].to_s
      "bin/goalner-worker #{GoalnerWorker.shell_word(argument)}"
    end

    private
      def matching(argument)
        project, name = argument.split("/", 2)
        if name && project.match?(PROJECT_FORMAT)
          scoped = named(name).select { |agent| agent["projects"].any? { |each| each.casecmp?(project) } }
          return scoped if scoped.any?
        end
        named(argument)
      end

      def named(name) = @list.select { |agent| agent["name"].casecmp?(name.strip) }

      def cloned?(agent) = agent["projects"].any? { |project| @runner.clones.key?(project) }

      def projects(agent)
        names = agent["projects"].join(", ")
        cloned?(agent) ? names : "#{names} (no clone here)"
      end

      def whereabouts(agent)
        lease = agent["lease"] or return "not running"
        since = Time.parse(lease["since"]).localtime.strftime("%Y-%m-%d %H:%M")
        lease["this_runner"] ? "runs here since #{since}" : "runs on #{lease.dig('runner', 'name')} since #{since}"
      end
  end
end
