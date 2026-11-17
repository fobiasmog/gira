import { api } from "./client.ts"
import type { Change, ChangeDetail, Id, TaskCard } from "./types.ts"

const base = (projectId: Id) => `/projects/${projectId}/changes`
// A change in a path: its id, or an open change's name.
const one = (projectId: Id, ref: Id | string) => `${base(projectId)}/${encodeURIComponent(ref)}`

export const changesApi = {
  // Open changes newest first; archived ones most recently archived first.
  list: (projectId: Id, view: "open" | "archived" = "open") => api.get<Change[]>(base(projectId), { view }),
  show: (projectId: Id, ref: Id | string) => api.get<ChangeDetail>(one(projectId, ref)),
  create: (projectId: Id, name: string) => api.post<Change>(base(projectId), { name }),
  archive: (projectId: Id, ref: Id | string) => api.post<Change>(`${one(projectId, ref)}/archival`),
  // Root, non-archived tasks in column order, done ones included.
  tasks: (projectId: Id, ref: Id | string) => api.get<TaskCard[]>(`${one(projectId, ref)}/tasks`),
}
