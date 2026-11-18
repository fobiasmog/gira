import { api, request, UPLOAD_TIMEOUT_MS } from "./client.ts"
import type { Change, ChangeDetail, ChangeFile, ChosenPhase, Comment, Id, TaskCard } from "./types.ts"

const base = (projectId: Id) => `/projects/${projectId}/changes`
// A change in a path: its id, or an open change's name.
const one = (projectId: Id, ref: Id | string) => `${base(projectId)}/${encodeURIComponent(ref)}`

export interface ChangeFields {
  idea?: string | null
  phase?: ChosenPhase
}

export const changesApi = {
  // Open changes newest first; archived ones most recently archived first.
  list: (projectId: Id, view: "open" | "archived" = "open") => api.get<Change[]>(base(projectId), { view }),
  show: (projectId: Id, ref: Id | string) => api.get<ChangeDetail>(one(projectId, ref)),
  // An empty idea is no idea.
  create: (projectId: Id, name: string, idea = "") => api.post<Change>(base(projectId), { name, idea: idea.trim() ? idea : null }),
  // The idea, while the change is in Idea, and the phase.
  update: (projectId: Id, ref: Id | string, fields: ChangeFields) => api.patch<ChangeDetail>(one(projectId, ref), fields),
  archive: (projectId: Id, ref: Id | string) => api.post<Change>(`${one(projectId, ref)}/archival`),
  // Root, non-archived tasks in column order, done ones included.
  tasks: (projectId: Id, ref: Id | string) => api.get<TaskCard[]>(`${one(projectId, ref)}/tasks`),
  // One OpenSpec file of the last import, such as specs/export/spec.md.
  file: (projectId: Id, ref: Id | string, path: string) => api.get<ChangeFile>(`${one(projectId, ref)}/file`, { path }),
  // The thread, oldest first.
  comments: (projectId: Id, ref: Id | string) => api.get<Comment[]>(`${one(projectId, ref)}/comments`),
  addComment: (projectId: Id, ref: Id | string, body: string, files: File[]) => {
    const form = new FormData()
    form.append("body", body)
    for (const file of files) form.append("attachments[]", file)
    return request<Comment>("POST", `${one(projectId, ref)}/comments`, { body: form, timeout: UPLOAD_TIMEOUT_MS })
  },
}
