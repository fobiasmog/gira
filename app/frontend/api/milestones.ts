import { api } from "./client.ts"
import type { Id, Milestone, MilestoneDetail } from "./types.ts"

const base = (projectId: Id) => `/projects/${projectId}/milestones`

export const milestonesApi = {
  list: (projectId: Id, view?: "deleted") => api.get<Milestone[]>(base(projectId), { view }),
  show: (projectId: Id, id: Id) => api.get<MilestoneDetail>(`${base(projectId)}/${id}`),
  create: (projectId: Id, title: string) => api.post<Milestone>(base(projectId), { title }),
  delete: (projectId: Id, id: Id) => api.delete(`${base(projectId)}/${id}`),
  recover: (projectId: Id, id: Id) => api.post<Milestone>(`${base(projectId)}/${id}/recovery`),
}
