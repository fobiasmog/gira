# How to connect MCP clients: the README's MCP section, linked from Settings
# → Connected apps (spec web-client, "Connected apps screen"), whose client
# code may name no third-party URL.
class McpGuidesController < ApplicationController
  GUIDE_URL = "https://github.com/fobiasmog/gira#mcp-server"

  allow_unauthenticated_access

  def show
    redirect_to GUIDE_URL, allow_other_host: true
  end
end
