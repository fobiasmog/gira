import { api } from "./client.ts"
import type { Agent, AgentChannel, AgentToken, ApiTokenAccess, Id, NewAgent, NewAgentToken, ProjectAgent, VisibleAgent } from "./types.ts"

// Agents (spec agents; spec web-client, "Agents screen"). An agent's id is
// its account's id, as in member lists.

export interface AgentTokenFields {
  name: string
  access: ApiTokenAccess
  channels: AgentChannel[]
}

export const agentsApi = {
  // The active agents the user can see, for adding one to another project.
  visible: () => api.get<VisibleAgent[]>("/agents"),
  // A project's agents, active and deleted.
  inProject: (projectId: Id) => api.get<ProjectAgent[]>(`/projects/${projectId}/agents`),
  create: (projectId: Id, name: string, token: AgentTokenFields, currentPassword: string) =>
    api.post<NewAgent>(`/projects/${projectId}/agents`, { name, token, current_password: currentPassword }),
  addToProject: (projectId: Id, agentId: Id) => api.post<Agent>(`/projects/${projectId}/agent_memberships`, { agent_id: agentId }),
  removeFromProject: (projectId: Id, agentId: Id) => api.delete(`/projects/${projectId}/members/${agentId}`),
  rename: (agentId: Id, name: string) => api.patch<Agent>(`/agents/${agentId}`, { name }),
  delete: (agentId: Id) => api.delete(`/agents/${agentId}`),
  restore: (agentId: Id) => api.post<Agent>(`/agents/${agentId}/restoration`),
  tokens: (agentId: Id) => api.get<AgentToken[]>(`/agents/${agentId}/tokens`),
  issueToken: (agentId: Id, token: AgentTokenFields, currentPassword: string) =>
    api.post<NewAgentToken>(`/agents/${agentId}/tokens`, { ...token, current_password: currentPassword }),
  revokeToken: (agentId: Id, tokenId: Id) => api.delete(`/agents/${agentId}/tokens/${tokenId}`),
}

// The choice the forms offer for where a token works.
export const CHANNEL_CHOICES = ["api", "mcp", "both"] as const
export type ChannelChoice = (typeof CHANNEL_CHOICES)[number]

export function channelsOf(choice: ChannelChoice): AgentChannel[] {
  return choice === "both" ? ["api", "mcp"] : [choice]
}

export function choiceOf(channels: AgentChannel[]): ChannelChoice {
  return channels.includes("api") && channels.includes("mcp") ? "both" : channels[0] ?? "api"
}

export const worksOn = (token: Pick<AgentToken, "channels">, channel: AgentChannel) => token.channels.includes(channel)

// A project's agents that are active, and its deleted ones.
export function activeAgents<T extends Agent>(agents: T[]): T[] {
  return agents.filter((agent) => !agent.deleted)
}

export function deletedAgents<T extends Agent>(agents: T[]): T[] {
  return agents.filter((agent) => agent.deleted)
}

// The agents the user can see that are not yet in the project.
export function addableAgents(visible: VisibleAgent[], projectId: Id): VisibleAgent[] {
  return visible.filter((agent) => !agent.projects.some((project) => project.id === projectId))
}

// The list once agent replaces the entry with its id, or joins it, by name.
export function withAgent<T extends Agent>(agents: T[], agent: T): T[] {
  return [...agents.filter((other) => other.id !== agent.id), agent].sort((a, b) => a.name.localeCompare(b.name) || a.id - b.id)
}

// What to paste into a terminal to add Goalner to Claude Code with a token.
// url is the MCP endpoint the server named when it issued the token: in
// development it is not on the application's origin.
export function mcpCommand(url: string, token: string): string {
  return `claude mcp add --transport http goalner ${url} --header "Authorization: Bearer ${token}"`
}

// The same connection for clients configured with an mcpServers block.
export function mcpConfig(url: string, token: string): string {
  return JSON.stringify({ mcpServers: { goalner: { type: "http", url, headers: { Authorization: `Bearer ${token}` } } } }, null, 2)
}
