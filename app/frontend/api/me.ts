import { api, request, UPLOAD_TIMEOUT_MS } from "./client.ts"
import type { ContactLinks, Language, Profile } from "./types.ts"

export interface ProfileChanges {
  name?: string
  lang?: Language
  contact_links?: ContactLinks
}

export const meApi = {
  show: () => api.get<Profile>("/me"),
  update: (changes: ProfileChanges) => api.patch<Profile>("/me", changes),
  updateAvatar: (file: File) => {
    const form = new FormData()
    form.append("avatar", file)
    return request<Profile>("PUT", "/me/avatar", { body: form, timeout: UPLOAD_TIMEOUT_MS })
  },
  updatePassword: (currentPassword: string, password: string) =>
    api.patch<void>("/me/password", { current_password: currentPassword, password }),
}
