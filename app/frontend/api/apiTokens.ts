import { api } from "./client.ts"
import type { ApiToken, ApiTokenAccess, Id, NewApiToken } from "./types.ts"

export interface ApiTokenFields {
  name: string
  project_id: Id
  access: ApiTokenAccess
  expires_in_days: number
  current_password: string
}

export const apiTokensApi = {
  list: () => api.get<ApiToken[]>("/me/api_tokens"),
  create: (fields: ApiTokenFields) => api.post<NewApiToken>("/me/api_tokens", fields),
  revoke: (id: Id) => api.delete(`/me/api_tokens/${id}`),
}
