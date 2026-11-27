import { api } from "./client.ts"
import type { Id, NewRunner, Runner } from "./types.ts"

// The user's runners (spec agent-runners; spec web-client, "Runners
// screen"). Creating one and rotating its secret ask for the current
// password, and are the only answers that carry the secret.
export const runnersApi = {
  list: () => api.get<Runner[]>("/me/runners"),
  create: (name: string, currentPassword: string) => api.post<NewRunner>("/me/runners", { name, current_password: currentPassword }),
  rotate: (runnerId: Id, currentPassword: string) =>
    api.post<NewRunner>(`/me/runners/${runnerId}/secret_rotation`, { current_password: currentPassword }),
  revoke: (runnerId: Id) => api.delete(`/me/runners/${runnerId}`),
}

// What to run on the machine to register it, or to give it a new secret.
export function registerCommand(url: string, secret: string): string {
  return `bin/goalner-worker register --url ${url} --token ${secret}`
}
