# The MCP server's Rack application, served by bin/mcp. It loads no Rails.
require_relative "lib/goalner_mcp"

GoalnerMcp.start_sentry
run GoalnerMcp.app
