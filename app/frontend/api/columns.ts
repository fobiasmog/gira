import { api } from "./client.ts"
import type { Column, Id } from "./types.ts"

// Every change answers with the project's columns in their new order.
const base = (projectId: Id) => `/projects/${projectId}/statuses`

export const columnsApi = {
  create: (projectId: Id, title: string) => api.post<Column[]>(base(projectId), { title }),
  rename: (projectId: Id, id: Id, title: string) => api.patch<Column[]>(`${base(projectId)}/${id}`, { title }),
  move: (projectId: Id, id: Id, position: number) => api.patch<Column[]>(`${base(projectId)}/${id}`, { position }),
  delete: (projectId: Id, id: Id) => api.delete<Column[]>(`${base(projectId)}/${id}`),
}
