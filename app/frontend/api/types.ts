// JSON shapes returned by the API, mirroring app/serializers and the inline
// JSON of app/controllers/api. Timestamps are ISO 8601 strings; dates
// (starts_on, ends_on) are YYYY-MM-DD.

export type Id = number
export type Timestamp = string
export type DateString = string
export type Language = "en" | "ru"

export const CONTACT_SERVICES = ["fb", "vk", "tg", "ig", "slack"] as const
export type ContactService = (typeof CONTACT_SERVICES)[number]
export type ContactLinks = Partial<Record<ContactService, string>>

export interface UserCard {
  id: Id
  name: string
  email_address: string
  avatar_url: string | null
}

export interface Profile extends UserCard {
  lang: Language
  contact_links: ContactLinks
  admin: boolean
}

export interface Project {
  id: Id
  title: string
  short_name: string
  owner_id: Id
  owned_by_me: boolean
}

export interface Column {
  id: Id
  title: string
  color: string | null
  position: number
  done: boolean
}

export interface Label {
  id: Id
  title: string
}

export interface TaskCard {
  id: Id
  number: number
  key: string
  title: string
  status_id: Id
  position: number | null
  parent_id: Id | null
  sprint_id: Id | null
  milestone_id: Id | null
  label_id: Id | null
  assignee_id: Id | null
  deadline: Timestamp | null
  important: boolean
  completed_at: Timestamp | null
  archived_at: Timestamp | null
  subtask_count: number
  subtask_done_count: number
  comment_count: number
}

export interface Subtask {
  id: Id
  number: number
  key: string
  title: string
  complete: boolean
}

export interface TaskDetail extends TaskCard {
  description: string | null
  origin_task_id: Id | null
  created_at: Timestamp
  creator: UserCard | null
  assignee: UserCard | null
  status: Pick<Column, "id" | "title" | "done">
  milestone: { id: Id; title: string } | null
  label: Label | null
  sprint: { id: Id; title: string } | null
  subtasks: Subtask[]
}

export interface Attachment {
  filename: string
  byte_size: number
  content_type: string
  url: string
  preview_url: string | null
}

export interface Comment {
  id: Id
  body: string
  author: UserCard
  created_at: Timestamp
  updated_at: Timestamp
  attachments: Attachment[]
}

export interface Invitation {
  id: Id
  email: string
  expires_at: Timestamp
  inviter_id: Id
}

export interface SprintSummary {
  id: Id
  title: string
  starts_on: DateString
  ends_on: DateString
}

export interface Sprint extends SprintSummary {
  active: boolean
  archived_at: Timestamp | null
  // by_status keys are column ids.
  task_counts: { by_status: Record<string, number>; total: number }
}

// A task in a sprint's task list: carried_to names the sprint holding the
// task's most recent carried-over copy.
export interface SprintTaskCard extends TaskCard {
  carried_to: { id: Id; title: string } | null
}

export interface Milestone {
  id: Id
  title: string
  deleted_at: Timestamp | null
  total: number
  done: number
}

export interface MilestoneDetail extends Milestone {
  tasks: TaskCard[]
}

export interface Board {
  project: Project
  columns: Column[]
  tasks: TaskCard[]
  members: UserCard[]
  labels: Label[]
  active_sprint: SprintSummary | null
}

export type ApiTokenAccess = "read" | "read_write"

// A personal API token. The value itself is never listed: only its last four
// characters.
export interface ApiToken {
  id: Id
  name: string
  project: Pick<Project, "id" | "title" | "short_name">
  access: ApiTokenAccess
  last_characters: string
  expires_at: Timestamp
  created_at: Timestamp
  last_used_at: Timestamp | null
}

// The creation response, the only one that carries the value.
export interface NewApiToken extends ApiToken {
  token: string
}

// A project's call: whether calls are offered at all, and the members in it.
export interface CallStatus {
  available: boolean
  participants: UserCard[]
}

// Where and how to join a project's call: the media server's WebSocket URL
// and a short-lived access token for it.
export interface CallToken {
  url: string
  token: string
}

export interface Announcement {
  id: Id
  body: string
  created_at: Timestamp
}

export interface StatisticsTask {
  id: Id
  key: string
  title: string
  important: boolean
}

export interface StatisticsProject {
  project: Pick<Project, "id" | "title" | "short_name">
  columns: { id: Id; title: string; tasks: StatisticsTask[] }[]
}

export interface Deadline extends StatisticsTask {
  deadline: Timestamp
  project_id: Id
}

export type FieldErrors = Record<string, string[]>

export interface ErrorEnvelope {
  error: { code: string; message: string; fields?: FieldErrors }
}
