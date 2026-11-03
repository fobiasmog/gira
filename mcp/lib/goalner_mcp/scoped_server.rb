module GoalnerMcp
  # The MCP server, listing only read-only tools to read-only connections
  # (spec mcp-server, "Tools for read-only connections"; add-mcp-oauth
  # design.md, decision 9). The SDK hands a tools/list handler the request's
  # credential only when the handler asks for server_context, so the built-in
  # handler is replaced with one that does, and paginates as the SDK does.
  # Personal tokens carry no scope and see every tool.
  class ScopedServer < MCP::Server
    def initialize(**options)
      super
      @handlers[MCP::Methods::TOOLS_LIST] = method(:list_tools_for)
    end

    private
      def list_tools_for(request, server_context:)
        credential = server_context.auth_info
        tools = @tools.values
        tools = tools.select { |tool| tool.annotations_value&.read_only_hint } if credential.respond_to?(:read_only_connection?) && credential.read_only_connection?

        page = paginate(tools, cursor: cursor_from(request), page_size: @page_size, request: request, &:to_h)
        apply_cache_metadata({ tools: page[:items], nextCursor: page[:next_cursor] }.compact)
      end
  end
end
