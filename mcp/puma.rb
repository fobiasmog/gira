# Puma for the MCP server, started by bin/mcp (add-mcp-server design.md,
# decision 10). One process with 16 threads: requests mostly wait on the API.
threads 16, 16

port ENV.fetch("MCP_PORT", 3100)
