# How to connect MCP clients: the README's MCP section, linked from Settings
# → Connected apps (spec web-client, "Connected apps screen"), whose client
# code may name no third-party URL. The URL is config.x.mcp.guide_url.
class McpGuidesController < ApplicationController
  allow_unauthenticated_access

  def show
    redirect_to Rails.configuration.x.mcp.guide_url, allow_other_host: true
  end
end
