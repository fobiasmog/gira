import { api } from "./client.ts"
import type { Announcement, Deadline, Id, StatisticsProject, UserCard } from "./types.ts"

// Endpoints about the signed-in user that are not their profile.
export const accountApi = {
  teammates: () => api.get<UserCard[]>("/teammates"),
  announcements: () => api.get<Announcement[]>("/announcements"),
  dismissAnnouncements: () => api.delete("/announcements"),
  overview: (userId?: Id) => api.get<StatisticsProject[]>("/statistics/overview", { user_id: userId }),
  deadlines: (userId?: Id) => api.get<Deadline[]>("/statistics/deadlines", { user_id: userId }),
  sendFeedback: (reason: string, message: string) => api.post<void>("/feedback", { reason, message }),
}
