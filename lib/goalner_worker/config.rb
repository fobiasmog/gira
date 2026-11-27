require "fileutils"
require "json"
require "yaml"

module GoalnerWorker
  # A refusal to go on: its message is printed, and the worker ends with
  # exit status 1.
  class Error < StandardError; end

  # A runner registered on this machine, for one Goalner address (spec
  # agent-worker, "Register a runner"): its secret, its name as Goalner
  # knows it, where its workspaces go, and the local clone of each project
  # it works on, by the project's short name.
  Runner = Struct.new(:url, :secret, :name, :workspaces, :clones, keyword_init: true) do
    def self.from_h(hash)
      new(url: hash["url"], secret: hash["secret"], name: hash["name"], workspaces: hash["workspaces"], clones: (hash["clones"] || {}).to_h)
    end

    def to_h
      { "url" => url, "secret" => secret, "name" => name, "workspaces" => workspaces, "clones" => clones.to_h }
    end
  end

  # The configuration file, runners.yml in $XDG_CONFIG_HOME/goalner or
  # ~/.config/goalner (add-runners-and-workspaces design.md, decision 5): a
  # list of runners, one per Goalner address. It holds runner secrets, so it
  # is kept readable and writable by its user alone, and the worker refuses
  # one that others can read or write, as ssh does.
  class Config
    attr_reader :path, :runners

    def self.default_path(env = ENV)
      base = env["XDG_CONFIG_HOME"].to_s.empty? ? File.join(Dir.home, ".config") : env["XDG_CONFIG_HOME"]
      File.join(base, "goalner", "runners.yml")
    end

    def self.normalize_url(url)
      url.to_s.strip.chomp("/")
    end

    def self.load(path = default_path)
      new(path).tap(&:read)
    end

    def initialize(path)
      @path = path
      @runners = []
    end

    def read
      return unless File.exist?(@path)

      check_permissions!
      data = YAML.safe_load_file(@path, aliases: true) || {}
      @runners = Array(data["runners"]).map { |hash| Runner.from_h(hash) }
    end

    def find(url)
      url = self.class.normalize_url(url)
      @runners.find { |runner| runner.url == url }
    end

    # The runner to start agents with: the one for url, or the only one.
    def choose(url)
      raise Error, "No runner is registered on this machine. Create one in Goalner (Settings, Runners) and run the command it shows." if @runners.empty?
      return find(url) || raise(Error, "No runner is registered for #{url}. Registered: #{@runners.map(&:url).join(', ')}.") if url

      return @runners.first if @runners.one?

      raise Error, "Several runners are registered: #{@runners.map(&:url).join(', ')}. Choose one with --url."
    end

    # Replaces the runner for its address, keeping the others.
    def put(runner)
      @runners = @runners.reject { |each| each.url == runner.url } + [ runner ]
    end

    # Writes the file with permissions 600, in a directory with permissions 700.
    def write
      directory = File.dirname(@path)
      FileUtils.mkdir_p(directory)
      File.chmod(0o700, directory)
      temporary = "#{@path}.#{Process.pid}.tmp"
      File.open(temporary, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
        # Through JSON, so that no two runners share a YAML anchor.
        file.write(YAML.dump(JSON.parse(JSON.generate({ "runners" => @runners.map(&:to_h) }))))
      end
      File.chmod(0o600, temporary)
      File.rename(temporary, @path)
    end

    private
      def check_permissions!
        mode = File.stat(@path).mode & 0o777
        return if (mode & 0o077).zero?

        raise Error, "#{@path} can be read or written by other users of this machine (permissions #{format('%o', mode)}), " \
          "and it holds runner secrets. Fix its permissions with: chmod 600 #{@path}"
      end
  end
end
