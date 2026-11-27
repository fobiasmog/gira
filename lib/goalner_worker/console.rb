require "json"

module GoalnerWorker
  # What the worker shows in its terminal (spec agent-worker, "Run a
  # request"): a line with the time for each of its own events, the run's
  # text, one short line per tool call, and the run's duration and cost at
  # its end. Secrets never reach it.
  class Console
    def initialize(out = $stdout)
      @out = out
      @out.sync = true if @out.respond_to?(:sync=)
    end

    def event(message)
      @out.puts "[#{Time.now.strftime('%H:%M:%S')}] #{message}"
    end

    # One line of a run's stream-json output.
    def run_line(line)
      message = JSON.parse(line)
      case message["type"]
      when "assistant" then assistant(message)
      when "system" then system(message)
      when "result" then result(message)
      end
    rescue JSON::ParserError
      @out.puts "  #{line.chomp}" unless line.strip.empty?
    end

    private
      def assistant(message)
        Array(message.dig("message", "content")).each do |block|
          case block["type"]
          when "text" then @out.puts block["text"].to_s.strip.gsub(/^/, "  ") unless block["text"].to_s.strip.empty?
          when "tool_use" then @out.puts "  → #{block['name']}#{tool_summary(block['input'])}"
          end
        end
      end

      def system(message)
        return unless message["subtype"] == "init"

        Array(message["mcp_servers"]).each do |server|
          event("MCP server #{server['name']} is #{server['status']}") unless server["status"] == "connected"
        end
      end

      def result(message)
        seconds = message["duration_ms"].to_i / 1000
        cost = message["total_cost_usd"] ? format(", $%.2f for the session so far", message["total_cost_usd"]) : ""
        outcome = message["is_error"] ? "ended with an error (#{message['subtype']})" : "ended"
        event("The run #{outcome} after #{seconds / 60}m #{seconds % 60}s#{cost}")
      end

      def tool_summary(input)
        return "" unless input.is_a?(Hash)

        detail = input["command"] || input["file_path"] || input["path"] || input["pattern"] || input["description"]
        detail ? ": #{detail.to_s.lines.first.to_s.strip[0, 100]}" : ""
      end
  end
end
