import type { ChangeEvent, ProjectAgent } from "../../api/types.ts"
import { agentState, type StatusLine } from "../../composables/changes.ts"
import { language, t } from "../../i18n/index.ts"
import { formatDateTime } from "../../i18n/format.ts"
import { personName } from "../../i18n/people.ts"

// The texts of requests and agents (spec web-client, "Requests on the change
// page" and "New change dialog"), in the viewer's language.

// An agent as the pickers offer it: free, on which change, or offline.
export function agentOption(agent: Pick<ProjectAgent, "name" | "online" | "working_on">): string {
  const state = agentState(agent)
  const name = agent.name
  if (state.kind === "offline") return t("changes.agentOffline", { name })
  if (state.kind === "free") return t("changes.agentFree", { name })
  return state.change ? t("changes.agentBusy", { name, change: state.change }) : t("changes.agentBusyElsewhere", { name })
}

// The status line of a change's request and agent.
export function statusText(line: StatusLine): string {
  switch (line.key) {
    case "blocked": return t("changePage.blocked", { name: line.agent.name })
    case "working": return t("changePage.working", { name: line.agent.name, time: formatDateTime(language.value, line.since) })
    case "waitingFree": return t("changePage.waitingFree")
    case "onChange": return t("changePage.onChange", { name: line.agent.name })
    case "picked": return t("changePage.picked", { name: line.agent.name })
    case "queued": {
      const name = line.agent.name
      const state = line.state
      if (state?.kind === "offline") return t("changePage.queuedOffline", { name })
      if (state?.kind === "busy") return state.change ? t("changePage.queuedBusy", { name, change: state.change }) : t("changePage.queuedBusyElsewhere", { name })
      return t("changePage.queued", { name })
    }
  }
}

// A line of the change's history in the thread.
export function historyText(event: ChangeEvent): string {
  const name = personName(event.actor)
  switch (event.kind) {
    case "phase": return t("changePage.movedLine", { name, phase: t(`changes.phases.${event.phase!}`) })
    case "import": return t("changePage.importedLine", { name, files: (event.paths ?? []).join(", ") })
    case "release": return t("changePage.releaseLine", { name, agent: event.agent ? personName(event.agent) : "" })
    case "block": return t("changePage.blockLine", { name })
    case "request": {
      const step = t(`changePage.requestSteps.${event.step!}`)
      return t(`changePage.${event.state!}Line`, { name, step })
    }
  }
}
