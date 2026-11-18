// JSON shapes returned by the API, mirroring app/serializers and the inline
// JSON of app/controllers/api. Timestamps are ISO 8601 strings.

export type Id = number
export type Timestamp = string
export type Language = "en" | "ru"

export const CONTACT_SERVICES = ["fb", "vk", "tg", "ig", "slack"] as const
export type ContactService = (typeof CONTACT_SERVICES)[number]
export type ContactLinks = Partial<Record<ContactService, string>>

// agent: an agent's account rather than a person's. deleted: true only for a
// deleted agent, which still appears on its past work.
export interface UserCard {
  id: Id
  name: string
  email_address: string
  avatar_url: string | null
  agent: boolean
  deleted: boolean
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
  // The change the task belongs to (spec changes); a subtask's is its card's.
  change_id: Id | null
  change: ChangeReference | null
  // Whether the task's mark is in its change's tasks.md: imports update it,
  // and it stays in its change.
  in_tasks_md: boolean
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
  created_at: Timestamp
  creator: UserCard | null
  assignee: UserCard | null
  status: Pick<Column, "id" | "title" | "done">
  label: Label | null
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

export interface ChangeReference {
  id: Id
  name: string
}

// Root, non-archived tasks; by_status keys are column ids.
export interface TaskCounts {
  by_status: Record<string, number>
  total: number
}

// A change (spec changes): open while archived_at is null.
// The phases of a change, in order. Done is reported, never chosen.
export const CHANGE_PHASES = ["idea", "exploring", "proposed", "implementing", "done"] as const
export type ChangePhase = (typeof CHANGE_PHASES)[number]
export type ChosenPhase = Exclude<ChangePhase, "done">

export interface Change extends ChangeReference {
  archived_at: Timestamp | null
  phase: ChangePhase
  // Its agent's context is full, or it has no open request and the newest
  // comment of its thread was written by an agent.
  waiting_for_people: boolean
  task_counts: TaskCounts
  // The open request, waiting or taken.
  request: ChangeRequest | null
  // Picked, or on the change; null for any free agent.
  agent: ChangeAgent | null
}

// Requests for the steps of a change (spec change-requests). People ask for
// all kinds but reply, which comments create.
export const REQUEST_KINDS = ["explore", "propose", "implement", "archive", "reply"] as const
export type RequestKind = (typeof REQUEST_KINDS)[number]
export type AskableKind = Exclude<RequestKind, "reply">
export type RequestState = "waiting" | "taken" | "done" | "failed" | "cancelled"

export interface ChangeRequest {
  id: Id
  kind: RequestKind
  state: RequestState
  change: ChangeReference & { phase: ChangePhase }
  requested_by: UserCard
  taken_by: UserCard | null
  // The agent that finished it, or who cancelled it.
  finished_by: UserCard | null
  created_at: Timestamp
  taken_at: Timestamp | null
  finished_at: Timestamp | null
}

// The agent of a change: on it once it took the change's first request,
// picked before. blocked_at: since when its context is full.
export interface ChangeAgent {
  user: UserCard
  on: boolean
  since: Timestamp | null
  blocked_at: Timestamp | null
}

// One line of a change's history: a phase move, an import with the files it
// brought, tasks.md included, a step of a request, the release of the
// change's agent, or a block because the agent's context is full.
export interface ChangeEvent {
  kind: "phase" | "import" | "request" | "release" | "block"
  actor: UserCard
  phase: ChosenPhase | null
  paths: string[] | null
  // The released agent.
  agent: UserCard | null
  step: RequestKind | null
  state: "asked" | "taken" | "done" | "failed" | "cancelled" | null
  created_at: Timestamp
}

// A file of a change's last import, as opening the change lists it.
export interface ChangeFileEntry {
  path: string
  length: number
}

export interface ChangeFile {
  path: string
  text: string
}

// An opened change, with its idea, history, files and last OpenSpec import
// (null until the first).
export interface ChangeDetail extends Change {
  idea: string | null
  imported_by: UserCard | null
  imported_at: Timestamp | null
  tasks_text: string | null
  history: ChangeEvent[]
  files: ChangeFileEntry[]
  cards: TaskCard[]
}

// The board of one open change, or of the tasks in no change (change: null),
// with the project's open changes, newest first.
export interface Board {
  project: Project
  columns: Column[]
  tasks: TaskCard[]
  members: UserCard[]
  labels: Label[]
  change: ChangeReference | null
  changes: Change[]
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

// An MCP connection: one client, such as claude.ai, reaching all of the
// user's projects with the access chosen at consent.
export interface Connection {
  id: Id
  client_name: string
  redirect_host: string | null
  access: ApiTokenAccess
  connected_at: Timestamp
  last_active_at: Timestamp
}

// Where an agent token works.
export type AgentChannel = "api" | "mcp"

// An agent, for the people who handle it. Its id is its account's id: the
// one member lists, assignees and comment authors carry.
export interface Agent extends UserCard {
  created_by: UserCard
  created_at: Timestamp
  deleted_at: Timestamp | null
}

// An agent in a project's list. removable: it belongs to another project
// too, so it can be removed from this one.
// checked_in_at: its last take of a request in the project; online while it
// is younger than 3 minutes. working_on: the open change it is on, unnamed
// when it is in a project the viewer does not share.
export interface ProjectAgent extends Agent {
  token_count: number
  removable: boolean
  checked_in_at: Timestamp | null
  online: boolean
  working_on: { id: Id | null; name: string | null; project_id: Id | null } | null
}

// An agent the user can see, with the projects they share.
export interface VisibleAgent extends Agent {
  projects: Pick<Project, "id" | "title" | "short_name">[]
}

// An agent's token. The value itself is never listed: only its last four
// characters.
export interface AgentToken {
  id: Id
  name: string
  issuer: UserCard
  access: ApiTokenAccess
  channels: AgentChannel[]
  last_characters: string
  created_at: Timestamp
  last_used_at: Timestamp | null
}

// The response that issues a token, the only one that carries the value.
export interface NewAgentToken extends AgentToken {
  token: string
  // The MCP endpoint, as the server knows it.
  mcp_url: string
}

// The creation response: the agent and its first token.
export interface NewAgent extends ProjectAgent {
  first_token: NewAgentToken
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
