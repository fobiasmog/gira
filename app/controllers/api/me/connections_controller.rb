# The signed-in user's MCP connections, behind Settings → Connected apps in
# the web client: the list, and Disconnect (spec mcp-authorization,
# "Connected apps"; add-mcp-oauth design.md, decision 7). Only the session
# opens it: a request with a personal API token or a connection token gets
# 403, so neither a token nor a connected app can list or end connections.
# Another user's connection is a 404.
class Api::Me::ConnectionsController < Api::BaseController
  def index
    render json: McpConnection.for(Current.user).map { |connection| serialize(connection) }
  end

  def destroy
    McpConnection.find(Current.user, params[:id]).disconnect!
    head :no_content
  end

  private
    def serialize(connection)
      {
        id: connection.id,
        client_name: connection.client_name,
        redirect_host: connection.redirect_host,
        access: connection.access,
        connected_at: connection.connected_at,
        last_active_at: connection.last_active_at
      }
    end
end
