import { api } from "./client.ts"
import type { Connection, Id } from "./types.ts"

// The signed-in user's MCP connections (spec mcp-authorization, "Connected apps").
export const connectionsApi = {
  list: () => api.get<Connection[]>("/me/connections"),
  disconnect: (id: Id) => api.delete(`/me/connections/${id}`),
}

// The README section on connecting MCP clients, linked when there are none.
// The server redirects there (McpGuidesController).
export const MCP_GUIDE_URL = "/docs/mcp"

// The list once the connection with id is disconnected.
export function withoutConnection(connections: Connection[], id: Id): Connection[] {
  return connections.filter((connection) => connection.id !== id)
}
