import type { App } from "vue"
import type { Pinia } from "pinia"
import * as Sentry from "@sentry/vue"
import { scrubEvent } from "./scrub.ts"

// Error reporting runs only where the server renders <meta name="sentry-dsn">
// (production), so one build serves every environment.
export function initSentry(app: App, pinia: Pinia) {
  const dsn = document.querySelector<HTMLMetaElement>('meta[name="sentry-dsn"]')?.content
  if (!dsn) return

  Sentry.init({
    app,
    dsn,
    // SDK 11's replacement for sendDefaultPii: false.
    dataCollection: {
      userInfo: false,
      cookies: false,
      httpHeaders: false,
      httpBodies: [],
      urlQueryParams: false,
      stackFrameVariables: false,
    },
    attachProps: false,
    // Default integrations only (no tracing, Replay or Feedback), without the
    // console and DOM breadcrumbs that could carry user content.
    integrations: (defaults) => [
      ...defaults.filter((integration) => !["Breadcrumbs", "Console"].includes(integration.name)),
      Sentry.breadcrumbsIntegration({ dom: false }),
    ],
    beforeSend: scrubEvent,
  })

  // Action names as breadcrumbs; never the stores' state.
  pinia.use(Sentry.createSentryPiniaPlugin({ attachPiniaState: false, stateTransformer: () => null }))
}

export function identifyUser(id: number) {
  Sentry.setUser({ id: String(id) })
}
