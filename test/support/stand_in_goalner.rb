require "json"
require "socket"

# A stand-in for Goalner's API, for tests of bin/goalner-worker (spec
# agent-worker): the runner endpoints, taking and finishing requests,
# opening a change, and reporting a full context, served over HTTP from a
# thread, with the state a test arranges and reads. Requests are recorded
# with their Authorization header.
#
# One agent, one runner secret and one project by default. The agent's
# requests: #waiting are handed out by takes, #taken is the one it holds.
class StandInGoalner
  SECRET = "glnr_runner_#{'s' * 40}".freeze
  PROJECT = { "id" => 1, "short_name" => "TEST" }.freeze

  attr_reader :requests, :finished, :workspaces, :leases, :checkpoints
  attr_accessor :agent, :projects, :waiting, :taken, :lease_refusal, :claim_status, :down, :blocked, :session_id, :earlier_takes

  def initialize
    @mutex = Mutex.new
    @requests = []
    @finished = []
    @workspaces = {}
    @leases = []
    @checkpoints = []
    @agent = { "id" => 6, "name" => "Fish", "model" => nil, "instructions" => nil }
    @projects = [ PROJECT ]
    @waiting = []
    @taken = nil
    @session_id = "11111111-2222-4333-8444-555555555555"
    @earlier_takes = 0
    @server = TCPServer.new("127.0.0.1", 0)
    @thread = Thread.new { loop { Thread.new(@server.accept) { |client| serve(client) } } }
  end

  def url = "http://127.0.0.1:#{@server.addr[1]}"

  def stop
    @thread.kill
    @server.close
  end

  def synchronize(&) = @mutex.synchronize(&)

  # A request of the agent's, as Goalner returns a taken one.
  def self.request(id, kind: "explore", change_id: 42, change: "export-csv", base_branch: "main")
    { "id" => id, "kind" => kind, "state" => "waiting", "change" => { "id" => change_id, "name" => change, "phase" => "exploring", "base_branch" => base_branch } }
  end

  def live_lease = synchronize { @leases.reverse.find { |lease| !lease["ended"] } }

  def run_token = live_lease&.fetch("token")

  # Takes with tokens, in order.
  def claims = synchronize { @requests.select { |request| request[:path].end_with?("/requests/claim") } }

  def calls(method, pattern) = synchronize { @requests.select { |request| request[:method] == method && request[:path].match?(pattern) } }

  private
    def serve(client)
      method, target = client.gets.to_s.split(" ")
      headers = {}
      while (line = client.gets) && line != "\r\n"
        name, value = line.split(":", 2)
        headers[name.downcase] = value.to_s.strip
      end
      body = headers["content-length"] ? client.read(headers["content-length"].to_i) : nil
      path, query = target.to_s.split("?", 2)
      token = headers["authorization"].to_s.delete_prefix("Bearer ")
      params = body.to_s.empty? ? {} : JSON.parse(body)
      status, answer = synchronize do
        @requests << { method:, path:, query:, token:, params: }
        down ? [ 503, { "error" => { "code" => "internal_error" } } ] : route(method, path, query, token, params)
      end
      text = answer.nil? ? "" : JSON.generate(answer)
      client.write("HTTP/1.1 #{status} X\r\nContent-Type: application/json\r\nContent-Length: #{text.bytesize}\r\nConnection: close\r\n\r\n#{text}")
    rescue IOError, SystemCallError
      nil
    ensure
      client.close
    end

    def route(method, path, query, token, params)
      runner_path = path.start_with?("/api/runner")
      return [ 401, { "error" => { "code" => runner_path ? "invalid_runner_secret" : "invalid_token" } } ] unless authorized?(runner_path, token)

      case [ method, path ]
      in [ "GET", "/api/runner" ] then [ 200, { "id" => 1, "name" => "laptop", "owner" => { "name" => "Bob" } } ]
      in [ "POST", %r{\A/api/runner/agents/(\d+)/lease\z} ] then lease(Integer($1))
      in [ "DELETE", %r{\A/api/runner/leases/(\d+)\z} ] then release(Integer($1))
      in [ "PUT", %r{\A/api/runner/changes/(\d+)/workspace\z} ] then record(Integer($1), params)
      in [ "PATCH", %r{\A/api/runner/workspaces/(\d+)\z} ] then report(Integer($1), params)
      in [ "GET", "/api/runner/workspaces" ] then [ 200, @workspaces.values.select { |workspace| workspace["to_remove"] && %w[active kept].include?(workspace["state"]) } ]
      in [ "POST", %r{\A/api/projects/(\d+)/requests/claim\z} ] then claim
      in [ "POST", %r{\A/api/projects/(\d+)/requests/(\d+)/finish\z} ] then finish(Integer($2), params)
      in [ "POST", %r{\A/api/projects/(\d+)/requests/context_full\z} ] then (@blocked = true) && [ 200, { "blocked" => true } ]
      in [ "GET", "/api/projects" ] then [ 200, @projects ]
      in [ "GET", %r{\A/api/projects/(\d+)/changes/(\d+)\z} ] then change_detail
      else [ 404, { "error" => { "code" => "not_found" } } ]
      end
    end

    def authorized?(runner_path, token)
      runner_path ? token == SECRET : token == @leases.reverse.find { |lease| !lease["ended"] }&.fetch("token")
    end

    def lease(agent_id)
      return [ 404, { "error" => { "code" => "not_found" } } ] unless agent_id == @agent["id"]
      return @lease_refusal if @lease_refusal

      @leases.each { |lease| lease["ended"] = true }
      lease = { "id" => @leases.size + 1, "token" => "glnr_run_#{@leases.size + 1}_#{'t' * 30}" }
      @leases << lease
      change = @taken && @taken["change"].merge("project" => PROJECT, "session_id" => @session_id, "workspace" => workspace_of(@taken),
        "request" => @taken.merge("state" => "taken"))
      [ 201, { "lease" => { "id" => lease["id"], "run_token" => lease["token"], "started_at" => "2026-11-27T14:05:00Z" }, "agent" => @agent,
        "projects" => @projects, "mcp_url" => "http://127.0.0.1:1/mcp", "change" => change } ]
    end

    def release(id)
      @leases.find { |lease| lease["id"] == id }&.store("ended", true)
      [ 204, nil ]
    end

    def claim
      return [ @claim_status, { "error" => {} } ] if @claim_status
      return [ 200, { "request" => nil } ] if @blocked

      @taken ||= @waiting.shift
      [ 200, { "request" => @taken && taken_json(@taken) } ]
    end

    def taken_json(request)
      request.merge("state" => "taken", "change" => request["change"].merge("session_id" => @session_id, "workspace" => workspace_of(request)))
    end

    def workspace_of(request)
      @workspaces[request.dig("change", "id")]&.reject { |key, _| key == "to_remove" }
    end

    def finish(id, params)
      return [ 422, { "error" => { "code" => "validation_failed" } } ] unless @taken && @taken["id"] == id

      @finished << { "id" => id, "outcome" => params["outcome"], "comment" => params["comment"] }
      # An archive request done archives the change, whose workspace is then to remove.
      @workspaces[@taken.dig("change", "id")]&.store("to_remove", true) if @taken["kind"] == "archive" && params["outcome"] == "done"
      @taken = nil
      [ 200, { "id" => id, "state" => params["outcome"] } ]
    end

    def record(change_id, params)
      existing = @workspaces[change_id]
      if existing
        return [ 422, { "error" => { "code" => "validation_failed", "fields" => { "path" => [ "is fixed" ] } } } ] unless existing.values_at("path", "branch") == params.values_at("path", "branch")

        return [ 200, existing ]
      end
      @workspaces[change_id] = { "id" => change_id + 1000, "runner" => { "name" => "laptop" }, "path" => params["path"], "branch" => params["branch"],
        "base_branch" => "main", "state" => "active", "checkpoint" => nil, "change" => { "id" => change_id, "name" => params["branch"] } }
      [ 200, @workspaces[change_id] ]
    end

    def report(id, params)
      workspace = @workspaces.values.find { |each| each["id"] == id } or return [ 404, { "error" => { "code" => "not_found" } } ]
      if params.key?("state")
        workspace["state"] = params["state"]
      else
        @checkpoints << params
        workspace["checkpoint"] = { "head_commit" => params["head_commit"], "uncommitted" => params["uncommitted"], "at" => "2026-11-27T14:10:00Z" }
      end
      [ 200, workspace ]
    end

    def change_detail
      history = Array.new(@earlier_takes + 1) { { "kind" => "request", "state" => "taken", "actor" => { "id" => @agent["id"] }, "created_at" => "2026-11-27T14:00:00.000Z" } }
      [ 200, { "agent" => { "since" => "2026-11-27T13:00:00.000Z" }, "history" => history } ]
    end
end
