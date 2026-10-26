import type { RouteLocationNormalized, RouteRecordRaw } from "vue-router"

export function parseId(value: unknown): number | null {
  const text = Array.isArray(value) ? value[0] : value
  return typeof text === "string" && /^[1-9]\d*$/.test(text) ? Number(text) : null
}

// Page components receive numeric ids as props.
const ids = (route: RouteLocationNormalized) => ({
  projectId: parseId(route.params.pid),
  ...(route.params.mid !== undefined && { milestoneId: parseId(route.params.mid) }),
  ...(route.params.tid !== undefined && { taskId: parseId(route.params.tid) }),
  ...(route.params.ref !== undefined && { taskRef: String(route.params.ref) }),
})

const id = "([1-9]\\d*)"

export const routes: RouteRecordRaw[] = [
  { path: "/", name: "dashboard", component: () => import("../pages/DashboardPage.vue") },
  { path: "/projects", name: "projects", component: () => import("../pages/ProjectsPage.vue") },
  { path: "/projects/new", name: "project-new", component: () => import("../pages/ProjectNewPage.vue") },
  { path: `/projects/:pid${id}`, redirect: (to) => ({ name: "board", params: to.params }) },
  { path: `/projects/:pid${id}/board`, name: "board", component: () => import("../pages/BoardPage.vue"), props: (route) => ({ ...ids(route), layout: "kanban" }) },
  { path: `/projects/:pid${id}/list`, name: "board-list", component: () => import("../pages/BoardPage.vue"), props: (route) => ({ ...ids(route), layout: "list" }) },
  { path: `/projects/:pid${id}/backlog`, name: "backlog", component: () => import("../pages/BacklogPage.vue"), props: ids },
  { path: `/projects/:pid${id}/sprints`, name: "sprints", component: () => import("../pages/SprintsPage.vue"), props: ids },
  { path: `/projects/:pid${id}/milestones`, name: "milestones", component: () => import("../pages/MilestonesPage.vue"), props: ids },
  { path: `/projects/:pid${id}/milestones/:mid${id}`, name: "milestone", component: () => import("../pages/MilestonePage.vue"), props: ids },
  { path: `/projects/:pid${id}/members`, name: "members", component: () => import("../pages/MembersPage.vue"), props: ids },
  { path: `/projects/:pid${id}/settings`, name: "project-settings", component: () => import("../pages/ProjectSettingsPage.vue"), props: ids },
  { path: `/projects/:pid${id}/archive`, name: "archive", component: () => import("../pages/ArchivePage.vue"), props: ids },
  { path: `/projects/:pid${id}/archive/:tid${id}`, name: "archived-task", component: () => import("../pages/ArchivedTaskPage.vue"), props: ids },
  { path: `/projects/:pid${id}/tasks/:ref`, name: "task", component: () => import("../pages/TaskPage.vue"), props: ids },
  { path: "/settings", redirect: { name: "settings-profile" } },
  { path: "/settings/profile", name: "settings-profile", component: () => import("../pages/ProfileSettingsPage.vue") },
  { path: "/settings/security", name: "settings-security", component: () => import("../pages/SecuritySettingsPage.vue") },
  { path: "/settings/api-tokens", name: "settings-api-tokens", component: () => import("../pages/ApiTokensSettingsPage.vue") },
  { path: "/:pathMatch(.*)*", name: "not-found", component: () => import("../pages/NotFoundPage.vue") },
]
