import type { RouteLocationNormalized, RouteLocationRaw, RouteRecordRaw } from "vue-router"
import type { Change } from "../api/types.ts"
import type { BoardTab } from "../stores/board.ts"

export function parseId(value: unknown): number | null {
  const text = Array.isArray(value) ? value[0] : value
  return typeof text === "string" && /^[1-9]\d*$/.test(text) ? Number(text) : null
}

// Page components receive numeric ids as props.
const ids = (route: RouteLocationNormalized) => ({
  projectId: parseId(route.params.pid),
  ...(route.params.tid !== undefined && { taskId: parseId(route.params.tid) }),
  ...(route.params.ref !== undefined && { taskRef: String(route.params.ref) }),
})

const id = "([1-9]\\d*)"

export type BoardLayout = "kanban" | "list"

// The board in either layout, on one tab (spec web-client, "Board change
// tabs"). A change's tab is under changes/, so a change named "other" keeps
// its own address.
const BOARD_PATHS: Record<BoardLayout, string> = { kanban: "board", list: "list" }
const BOARD_NAMES: Record<BoardLayout, string> = { kanban: "board", list: "board-list" }

const boardPage = () => import("../pages/BoardPage.vue")
const boardRoutes = (layout: BoardLayout): RouteRecordRaw[] => {
  const path = `/projects/:pid${id}/${BOARD_PATHS[layout]}`
  const name = BOARD_NAMES[layout]
  const props = (tab: (route: RouteLocationNormalized) => BoardTab) => (route: RouteLocationNormalized) => ({ ...ids(route), layout, tab: tab(route) })
  return [
    { path, name, component: boardPage, props: props(() => ({ kind: "default" })) },
    { path: `${path}/other`, name: `${name}-other`, component: boardPage, props: props(() => ({ kind: "other" })) },
    { path: `${path}/changes/:name`, name: `${name}-change`, component: boardPage, props: props((route) => ({ kind: "change", name: String(route.params.name) })) },
  ]
}

// Where a tab of the board is.
export function boardLocation(projectId: number, layout: BoardLayout, tab: BoardTab): RouteLocationRaw {
  const name = BOARD_NAMES[layout]
  if (tab.kind === "change") return { name: `${name}-change`, params: { pid: projectId, name: tab.name } }
  if (tab.kind === "other") return { name: `${name}-other`, params: { pid: projectId } }
  return { name, params: { pid: projectId } }
}

// A change's page (spec web-client, "Change page"): an open change by its
// name, an archived one by its id, so that the address keeps showing the
// same change. A name made only of digits would be read as an id, so such a
// change goes by its id too.
export function changeLocation(projectId: number, change: Pick<Change, "id" | "name" | "archived_at">): RouteLocationRaw {
  const byName = change.archived_at === null && !/^\d+$/.test(change.name)
  return { name: "change", params: { pid: projectId, change: byName ? change.name : String(change.id) } }
}

const changeProps = (route: RouteLocationNormalized) => ({ projectId: parseId(route.params.pid), changeRef: String(route.params.change) })

export const routes: RouteRecordRaw[] = [
  { path: "/", name: "dashboard", component: () => import("../pages/DashboardPage.vue") },
  { path: "/projects", name: "projects", component: () => import("../pages/ProjectsPage.vue") },
  { path: "/projects/new", name: "project-new", component: () => import("../pages/ProjectNewPage.vue") },
  { path: `/projects/:pid${id}`, redirect: (to) => ({ name: "board", params: to.params }) },
  ...boardRoutes("kanban"),
  ...boardRoutes("list"),
  { path: `/projects/:pid${id}/changes`, name: "changes", component: () => import("../pages/ChangesPage.vue"), props: ids },
  { path: `/projects/:pid${id}/changes/:change`, name: "change", component: () => import("../pages/ChangePage.vue"), props: changeProps },
  { path: `/projects/:pid${id}/members`, name: "members", component: () => import("../pages/MembersPage.vue"), props: ids },
  { path: `/projects/:pid${id}/agents`, name: "agents", component: () => import("../pages/ProjectAgentsPage.vue"), props: ids },
  { path: `/projects/:pid${id}/settings`, name: "project-settings", component: () => import("../pages/ProjectSettingsPage.vue"), props: ids },
  { path: `/projects/:pid${id}/archive`, name: "archive", component: () => import("../pages/ArchivePage.vue"), props: ids },
  { path: `/projects/:pid${id}/archive/:tid${id}`, name: "archived-task", component: () => import("../pages/ArchivedTaskPage.vue"), props: ids },
  { path: `/projects/:pid${id}/tasks/:ref`, name: "task", component: () => import("../pages/TaskPage.vue"), props: ids },
  { path: "/settings", redirect: { name: "settings-profile" } },
  { path: "/settings/profile", name: "settings-profile", component: () => import("../pages/ProfileSettingsPage.vue") },
  { path: "/settings/security", name: "settings-security", component: () => import("../pages/SecuritySettingsPage.vue") },
  { path: "/settings/api-tokens", name: "settings-api-tokens", component: () => import("../pages/ApiTokensSettingsPage.vue") },
  { path: "/settings/runners", name: "settings-runners", component: () => import("../pages/RunnersSettingsPage.vue") },
  { path: "/settings/connected-apps", name: "settings-connected-apps", component: () => import("../pages/ConnectedAppsSettingsPage.vue") },
  { path: "/:pathMatch(.*)*", name: "not-found", component: () => import("../pages/NotFoundPage.vue") },
]
