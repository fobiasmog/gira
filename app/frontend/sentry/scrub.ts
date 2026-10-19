import type { Breadcrumb, ErrorEvent } from "@sentry/vue"

const KEPT_BREADCRUMBS = new Set(["navigation", "fetch", "xhr", "pinia.action"])
const KEPT_HTTP_DATA = ["method", "url", "status_code"] as const

function scrubBreadcrumb(breadcrumb: Breadcrumb): Breadcrumb | null {
  if (!breadcrumb.category || !KEPT_BREADCRUMBS.has(breadcrumb.category)) return null
  if (breadcrumb.category !== "fetch" && breadcrumb.category !== "xhr") return breadcrumb

  const data: Record<string, unknown> = {}
  for (const key of KEPT_HTTP_DATA) if (breadcrumb.data?.[key] !== undefined) data[key] = breadcrumb.data[key]
  return { ...breadcrumb, data }
}

// Error reports keep the stack trace, the URL and the user's id, and nothing
// that could hold what people wrote: no request bodies, store state, extra
// data, console output or UI breadcrumbs.
export function scrubEvent(event: ErrorEvent): ErrorEvent {
  if (event.request) {
    delete event.request.data
    delete event.request.cookies
    delete event.request.query_string
  }
  if (event.user) event.user = event.user.id === undefined ? {} : { id: event.user.id }
  delete event.extra
  if (event.contexts) {
    delete event.contexts.state
    delete event.contexts.pinia
  }
  if (event.breadcrumbs) {
    event.breadcrumbs = event.breadcrumbs.map(scrubBreadcrumb).filter((b): b is Breadcrumb => b !== null)
  }
  return event
}
