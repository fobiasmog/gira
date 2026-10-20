import { api, request, UPLOAD_TIMEOUT_MS } from "./client.ts"
import type { Board, Comment, Id, TaskCard, TaskDetail } from "./types.ts"

export interface TaskFields {
  title?: string
  description?: string | null
  deadline?: string | null
  important?: boolean
  assignee_id?: Id | null
  milestone_id?: Id | null
}

// Without status_id the task goes to the first column. sprint_id, when
// present, wins (null: no sprint); when absent, a task created on a column
// joins the active sprint and any other task joins no sprint.
export interface NewTask extends TaskFields {
  title: string
  status_id?: Id
  label_id?: Id | null
  sprint_id?: Id | null
}

// sprint_id, when present, also moves the task into that sprint (null: none).
export interface Placement {
  status_id: Id
  position: number
  sprint_id?: Id | null
}

export type TaskView = "board" | "backlog" | "backlog_done" | "archived"

const base = (projectId: Id) => `/projects/${projectId}/tasks`

export const tasksApi = {
  board: (projectId: Id) => api.get<Board>(`/projects/${projectId}/board`),
  list: (projectId: Id, view: TaskView) => api.get<TaskCard[]>(base(projectId), { view }),
  show: (projectId: Id, ref: string | Id) => api.get<TaskDetail>(`${base(projectId)}/${encodeURIComponent(ref)}`),
  create: (projectId: Id, fields: NewTask) => api.post<TaskDetail>(base(projectId), fields),
  update: (projectId: Id, id: Id, fields: TaskFields) => api.patch<TaskDetail>(`${base(projectId)}/${id}`, fields),
  archive: (projectId: Id, id: Id) => api.delete(`${base(projectId)}/${id}`),
  place: (projectId: Id, id: Id, placement: Placement) => api.patch<TaskCard>(`${base(projectId)}/${id}/placement`, placement),
  setLabel: (projectId: Id, id: Id, labelId: Id | null) =>
    labelId === null
      ? api.delete<TaskCard>(`${base(projectId)}/${id}/label`)
      : api.patch<TaskCard>(`${base(projectId)}/${id}/label`, { label_id: labelId }),
  setSprint: (projectId: Id, id: Id, sprintId: Id | null) => api.patch<TaskCard>(`${base(projectId)}/${id}/sprint`, { sprint_id: sprintId }),
  addSubtask: (projectId: Id, id: Id, title: string) => api.post<TaskCard>(`${base(projectId)}/${id}/subtasks`, { title }),
  setComplete: (projectId: Id, id: Id, complete: boolean) =>
    complete
      ? api.patch<TaskCard>(`${base(projectId)}/${id}/completion`)
      : api.delete<TaskCard>(`${base(projectId)}/${id}/completion`),
  comments: (projectId: Id, id: Id) => api.get<Comment[]>(`${base(projectId)}/${id}/comments`),
  addComment: (projectId: Id, id: Id, body: string, files: File[]) => {
    const form = new FormData()
    form.append("body", body)
    for (const file of files) form.append("attachments[]", file)
    return request<Comment>("POST", `${base(projectId)}/${id}/comments`, { body: form, timeout: UPLOAD_TIMEOUT_MS })
  },
  updateComment: (id: Id, body: string) => api.patch<Comment>(`/comments/${id}`, { body }),
  deleteComment: (id: Id) => api.delete(`/comments/${id}`),
}
