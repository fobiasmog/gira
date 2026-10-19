import { api } from "./client.ts"
import type { DateString, Id, Sprint } from "./types.ts"

export interface NewSprint {
  title: string
  starts_on: DateString
  ends_on: DateString
  activate?: boolean
  carry_over?: boolean
}

const base = (projectId: Id) => `/projects/${projectId}/sprints`

export const sprintsApi = {
  list: (projectId: Id, view: "all" | "available" | "archived" = "all") => api.get<Sprint[]>(base(projectId), { view }),
  create: (projectId: Id, sprint: NewSprint) => api.post<Sprint>(base(projectId), sprint),
  activate: (projectId: Id, id: Id) => api.post<Sprint>(`${base(projectId)}/${id}/activation`),
  archive: (projectId: Id, id: Id, carryToSprintId: Id | null) =>
    api.post<Sprint>(`${base(projectId)}/${id}/archival`, { carry_to_sprint_id: carryToSprintId }),
}
