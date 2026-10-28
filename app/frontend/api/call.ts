import { api } from "./client.ts"
import type { CallStatus, CallToken, Id } from "./types.ts"

export const callApi = {
  getCall: (projectId: Id) => api.get<CallStatus>(`/projects/${projectId}/call`),
  createToken: (projectId: Id) => api.post<CallToken>(`/projects/${projectId}/call/token`),
}
