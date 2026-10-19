import { api } from "./client.ts"
import type { Id, Label } from "./types.ts"

export const labelsApi = {
  list: (projectId: Id) => api.get<Label[]>(`/projects/${projectId}/labels`),
  create: (projectId: Id, title: string) => api.post<Label>(`/projects/${projectId}/labels`, { title }),
}
