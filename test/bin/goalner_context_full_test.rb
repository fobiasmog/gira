require "test_helper"
require "open3"
require "socket"

# bin/goalner-context-full, the PreCompact hook of the goalner-worker skill
# (spec change-requests, "Full context"; add-change-requests design.md,
# decision 13), against a stand-in for Goalner's API: it reports a full
# context in every project the token reaches, and stops the compaction (exit
# 2) when one of them blocks the agent or Goalner cannot be asked.
class GoalnerContextFullTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("bin/goalner-context-full").to_s

  # Answers each request with answers["METHOD /path"], as JSON, or 404; and
  # records the requests with their Authorization header.
  class StubApi
    attr_reader :requests

    def initialize(answers)
      @answers = answers
      @requests = []
      @server = TCPServer.new("127.0.0.1", 0)
      @thread = Thread.new { loop { serve(@server.accept) } }
    end

    def url = "http://127.0.0.1:#{@server.addr[1]}"

    def stop
      @thread.kill
      @server.close
    end

    private
      def serve(client)
        request_line = client.gets.to_s
        headers = {}
        while (line = client.gets) && line != "\r\n"
          name, value = line.split(":", 2)
          headers[name.downcase] = value.strip
        end
        client.read(headers["content-length"].to_i) if headers["content-length"]
        key = request_line.split(" ").first(2).join(" ")
        @requests << [ key, headers["authorization"] ]
        body = @answers.key?(key) ? JSON.generate(@answers[key]) : '{"error":{}}'
        status = @answers.key?(key) ? "200 OK" : "404 Not Found"
        client.write("HTTP/1.1 #{status}\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      ensure
        client.close
      end
  end

  def run_hook(api, token: "glnr_fish")
    env = { "GOALNER_URL" => api&.url || "http://127.0.0.1:1", "GOALNER_TOKEN" => token }
    _output, errors, status = Open3.capture3(env, SCRIPT, stdin_data: { hook_event_name: "PreCompact", trigger: "auto" }.to_json)
    [ status.exitstatus, errors ]
  end

  def with_api(answers)
    api = StubApi.new(answers)
    yield api
  ensure
    api&.stop
  end

  test "blocked in one project: the compaction is stopped, and every project was told with the agent's token" do
    with_api("GET /api/projects" => [ { id: 1 }, { id: 2 } ],
      "POST /api/projects/1/requests/context_full" => { blocked: false },
      "POST /api/projects/2/requests/context_full" => { blocked: true }) do |api|
      status, errors = run_hook(api)

      assert_equal 2, status
      assert_match(/Goalner blocked its change/, errors)
      assert_equal [ "GET /api/projects", "POST /api/projects/1/requests/context_full", "POST /api/projects/2/requests/context_full" ], api.requests.map(&:first)
      assert_equal [ "Bearer glnr_fish" ], api.requests.map(&:last).uniq
    end
  end

  test "not blocked anywhere: the compaction runs" do
    with_api("GET /api/projects" => [ { id: 1 } ], "POST /api/projects/1/requests/context_full" => { blocked: false }) do |api|
      assert_equal [ 0, "" ], run_hook(api)
    end
  end

  test "no token, a refused request or no server: the compaction is stopped, saying why" do
    with_api("GET /api/projects" => [ { id: 1 } ]) do |api|
      status, errors = run_hook(api)
      assert_equal 2, status
      assert_match(/answered 404/, errors)

      status, errors = run_hook(api, token: "")
      assert_equal 2, status
      assert_match(/GOALNER_TOKEN is not set/, errors)
    end

    assert_equal 2, run_hook(nil).first
  end
end
