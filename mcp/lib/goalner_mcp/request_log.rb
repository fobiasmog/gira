module GoalnerMcp
  # One log line per MCP request (spec mcp-server, "Privacy of MCP logs";
  # add-mcp-server design.md, decision 9): the request id, the JSON-RPC method,
  # the tool, the API status (or -), the result and the duration. Nothing
  # else: no headers, arguments or bodies. A tool name is logged only when it
  # is one of the server's tools, so a client cannot write arguments into the
  # log under its name.
  #
  # An exception that escapes the application is reported and answered with
  # a generic 500.
  class RequestLog
    MAX_BODY_BYTES = 4 * 1024 * 1024
    REQUEST_ID = /\A[\w\-]{1,128}\z/
    RPC_METHOD = /\A[\w\/]{1,64}\z/
    INTERNAL_ERROR = { jsonrpc: "2.0", id: nil, error: { code: -32603, message: "Internal error" } }.freeze

    def initialize(app, tool_names:)
      @app = app
      @tool_names = tool_names.to_set
    end

    def call(env)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      rpc_method, tool = rpc_names(env)
      status, headers, body = @app.call(env)
      write(env, started, rpc_method, tool, result(status, body))
      [ status, headers, body ]
    rescue StandardError => error
      GoalnerMcp.report(error)
      write(env, started, rpc_method, tool, "error")
      [ 500, { "content-type" => "application/json" }, [ JSON.generate(INTERNAL_ERROR) ] ]
    end

    private
      # The JSON-RPC method and the tool it calls, read from the body, which
      # is then rewound for the transport.
      def rpc_names(env)
        input = env["rack.input"]
        return unless env["REQUEST_METHOD"] == "POST" && input.respond_to?(:rewind)

        raw = input.read(MAX_BODY_BYTES)
        input.rewind
        message = JSON.parse(raw.to_s)
        return unless message.is_a?(Hash)

        rpc_method = message["method"] if message["method"].is_a?(String) && RPC_METHOD.match?(message["method"])
        tool = message.dig("params", "name") if rpc_method == "tools/call" && message["params"].is_a?(Hash)
        [ rpc_method, (tool if @tool_names.include?(tool)) || (tool && "unknown") ]
      rescue JSON::ParserError
        nil
      end

      def result(status, body)
        return "unauthorized" if status == 401
        return "error" unless status == 200
        return "ok" unless body.is_a?(Array)

        response = JSON.parse(body.join)
        if response["error"] then "error"
        elsif response.dig("result", "isError") then "tool_error"
        else "ok"
        end
      rescue JSON::ParserError
        "ok"
      end

      def write(env, started, rpc_method, tool, result)
        credential = env[MCP::Server::OAuth::ENV_KEY]
        api_status = credential.api_status if credential.respond_to?(:api_status)
        request_id = env["HTTP_X_REQUEST_ID"].to_s[REQUEST_ID] || SecureRandom.uuid
        duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)

        GoalnerMcp.logger.info("mcp request_id=#{request_id} method=#{rpc_method || "-"} tool=#{tool || "-"} " \
          "api_status=#{api_status || "-"} result=#{result} duration_ms=#{duration}")
      end
  end
end
