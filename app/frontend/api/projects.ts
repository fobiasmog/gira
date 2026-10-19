import { api } from "./client.ts"
import type { Id, Invitation, Project, UserCard } from "./types.ts"

export interface ProjectFields {
  title?: string
  short_name?: string
}

export const projectsApi = {
  list: () => api.get<Project[]>("/projects"),
  show: (id: Id) => api.get<Project>(`/projects/${id}`),
  create: (fields: ProjectFields) => api.post<Project>("/projects", fields),
  update: (id: Id, fields: ProjectFields) => api.patch<Project>(`/projects/${id}`, fields),
  archive: (id: Id) => api.delete(`/projects/${id}`),
  leave: (id: Id) => api.delete(`/projects/${id}/membership`),
  members: (id: Id) => api.get<UserCard[]>(`/projects/${id}/members`),
  removeMember: (id: Id, userId: Id) => api.delete(`/projects/${id}/members/${userId}`),
  invitations: (id: Id) => api.get<Invitation[]>(`/projects/${id}/invitations`),
  invite: (id: Id, email: string) => api.post<{ message: string }>(`/projects/${id}/invitations`, { email }),
  revokeInvitation: (id: Id, invitationId: Id) => api.delete(`/projects/${id}/invitations/${invitationId}`),
}
