require "test_helper"
require "support/goalner_worker_harness"

# bin/goalner-worker register (spec agent-worker, "Register a runner" and
# "Configuration file safety"; add-runners-and-workspaces design.md,
# decision 5).
class GoalnerWorkerRegisterTest < ActiveSupport::TestCase
  include GoalnerWorkerHarness

  def register(*args, token: StandInGoalner::SECRET, url: @api.url)
    run_worker("register", "--url", url, *([ "--token", token ] if token), *args)
  end

  def saved = YAML.safe_load_file(config_path)["runners"]

  test "register: the runner's name is printed, and runners.yml holds the runner, readable and writable only by the user" do
    clone = create_clone

    status, output = register("--clone", "TEST=#{clone}")

    assert_equal 0, status, output
    assert_match(/Registered runner "laptop" of Bob for #{Regexp.escape(@api.url)}/, output)
    assert_match(/TEST: #{Regexp.escape(clone)}/, output)
    assert_equal [ { "url" => @api.url, "secret" => StandInGoalner::SECRET, "name" => "laptop", "workspaces" => workspaces_root, "clones" => { "TEST" => clone } } ], saved
    assert_equal 0o600, File.stat(config_path).mode & 0o777
    assert_equal 0o700, File.stat(File.dirname(config_path)).mode & 0o777
    assert_not_includes output, StandInGoalner::SECRET
    assert_equal [ [ "GET", "/api/runner", StandInGoalner::SECRET ] ], @api.requests.map { |request| request.values_at(:method, :path, :token) }
  end

  test "a second Goalner: both runners are kept" do
    register("--clone", "TEST=#{create_clone}")
    other = StandInGoalner.new

    status, output = register(url: other.url)

    assert_equal 0, status, output
    assert_equal [ @api.url, other.url ], saved.map { |runner| runner["url"] }
  ensure
    other&.stop
  end

  test "rejected secret: exit status 1, and runners.yml is unchanged" do
    register("--clone", "TEST=#{create_clone}")
    before = File.read(config_path)

    status, output = register("--clone", "MNT=#{create_clone('mnt')}", token: "glnr_runner_wrong")

    assert_equal 1, status
    assert_match(/rejected the runner secret/, output)
    assert_equal before, File.read(config_path)
  end

  test "a project added later: the saved secret is checked and kept, and the runner has clones of both" do
    test_clone = create_clone
    register("--clone", "TEST=#{test_clone}")
    mnt = create_clone("mynewthing")

    status, output = register("--clone", "MNT=#{mnt}", token: nil)

    assert_equal 0, status, output
    assert_equal({ "TEST" => test_clone, "MNT" => mnt }, saved.sole["clones"])
    assert_equal StandInGoalner::SECRET, saved.sole["secret"]
    assert_equal 2, @api.calls("GET", %r{\A/api/runner\z}).count { |request| request[:token] == StandInGoalner::SECRET }
  end

  test "registering again replaces a project's clone, the secret and the workspaces root when given" do
    register("--clone", "TEST=#{create_clone}")
    moved = create_clone("moved")

    status, output = register("--clone", "TEST=#{moved}", "--workspaces", File.join(@tmp, "elsewhere"))

    assert_equal 0, status, output
    assert_equal [ { "TEST" => moved }, File.join(@tmp, "elsewhere") ], saved.sole.values_at("clones", "workspaces")
  end

  test "unknown address without a secret: exit status 1, saying the secret is needed, and nothing is written" do
    status, output = register(token: nil)

    assert_equal 1, status
    assert_match(/secret is needed for a new address/, output)
    assert_not File.exist?(config_path)
    assert_empty @api.requests
  end

  test "no OpenSpec in the clone: a reminder to run openspec init there, the clone saved, and exit status 0" do
    clone = create_clone("mynewthing", openspec: false)

    status, output = register("--clone", "MNT=#{clone}")

    assert_equal 0, status, output
    assert_match(/#{Regexp.escape(clone)} has no openspec\/ folder. Run `openspec init` there and commit it/, output)
    assert_equal({ "MNT" => clone }, saved.sole["clones"])
  end

  test "a clone path that is not a git working copy, or a malformed clone: exit status 1, and nothing is written" do
    plain = File.join(@tmp, "plain").tap { |path| FileUtils.mkdir_p(path) }

    status, output = register("--clone", "TEST=#{plain}")
    assert_equal 1, status
    assert_match(/is not a git working copy/, output)

    status, = register("--clone", "test=#{create_clone}")
    assert_equal 1, status
    assert_not File.exist?(config_path)
  end

  test "readable by others: register and the worker end with exit status 1, naming the file and chmod 600" do
    register("--clone", "TEST=#{create_clone}")
    File.chmod(0o644, config_path)

    [ register(token: nil), run_worker(agent_id.to_s) ].each do |status, output|
      assert_equal 1, status
      assert_includes output, config_path
      assert_includes output, "chmod 600 #{config_path}"
    end
    assert_empty @api.calls("POST", /lease/)
  end
end
