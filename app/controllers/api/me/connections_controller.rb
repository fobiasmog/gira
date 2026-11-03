# The signed-in user's MCP connections (spec mcp-authorization, "Connected
# apps"; add-mcp-oauth design.md, decision 7). Not opened to tokens: API
# tokens and connections get 403. Another user's connection is a 404.
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
