import type { IconName } from "../components/ui/AppIcon.vue"
import type { MessageKey } from "../i18n/index.ts"

// The sections of a project, as listed in the navigation and named in the
// header's breadcrumb. `also` lists the routes shown inside the section.
export interface ProjectSection {
  name: string
  label: MessageKey
  icon: IconName
  also?: string[]
  ownerOnly?: boolean
}

export const projectSections: ProjectSection[] = [
  { name: "board", label: "navigation.board", icon: "view_kanban", also: ["board-list", "task"] },
  { name: "backlog", label: "navigation.backlog", icon: "inbox" },
  { name: "sprints", label: "navigation.sprints", icon: "sprint" },
  { name: "milestones", label: "navigation.milestones", icon: "flag", also: ["milestone"] },
  { name: "members", label: "navigation.members", icon: "group" },
  { name: "archive", label: "navigation.archive", icon: "archive", also: ["archived-task"] },
  { name: "project-settings", label: "navigation.projectSettings", icon: "settings", ownerOnly: true },
]

export function sectionOf(routeName: unknown): ProjectSection | null {
  const name = String(routeName)
  return projectSections.find((section) => section.name === name || section.also?.includes(name)) ?? null
}
