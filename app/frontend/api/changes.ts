import { api, request, UPLOAD_TIMEOUT_MS } from "./client.ts"
import type { AskableKind, Change, ChangeDetail, ChangeFile, ChangeRequest, ChosenPhase, Comment, Id, TaskCard } from "./types.ts"

const base = (projectId: Id) => `/projects/${projectId}/changes`
// A change in a path: its id, or an open change's name.
const one = (projectId: Id, ref: Id | string) => `${base(projectId)}/${encodeURIComponent(ref)}`

export interface ChangeFields {
  idea?: string | null
  phase?: ChosenPhase
  // An agent's id to pick, or null for any free agent.
  agent?: Id | null
}

export const changesApi = {
  // Open changes newest first; archived ones most recently archived first.
  list: (projectId: Id, view: "open" | "archived" = "open") => api.get<Change[]>(base(projectId), { view }),
  show: (projectId: Id, ref: Id | string) => api.get<ChangeDetail>(one(projectId, ref)),
  // An empty idea is no idea; no agent is any free agent.
  create: (projectId: Id, name: string, idea = "", agent: Id | null = null) =>
    api.post<Change>(base(projectId), { name, idea: idea.trim() ? idea : null, agent }),
  // The idea, while the change is in Idea, and the phase.
  update: (projectId: Id, ref: Id | string, fields: ChangeFields) => api.patch<ChangeDetail>(one(projectId, ref), fields),
  archive: (projectId: Id, ref: Id | string) => api.post<Change>(`${one(projectId, ref)}/archival`),
  // Asks for a step, with the comment field's text, if any, as its comment.
  askStep: (projectId: Id, ref: Id | string, kind: AskableKind, comment = "") =>
    api.post<ChangeRequest>(`${one(projectId, ref)}/requests`, comment.trim() ? { kind, comment } : { kind }),
  cancelRequest: (projectId: Id, requestId: Id) => api.post<ChangeRequest>(`/projects/${projectId}/requests/${requestId}/cancellation`),
  // Cancels the taken request, ends a block, and leaves the change with no agent.
  releaseAgent: (projectId: Id, ref: Id | string) => api.post<ChangeDetail>(`${one(projectId, ref)}/agent_release`),
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
