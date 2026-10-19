import "../styles/layers.css"
import { createApp, type Component } from "vue"
import { createPinia } from "pinia"
import App from "../App.vue"
import { router } from "../router/index.ts"
import { useUiStore } from "../stores/ui.ts"
import { initSentry } from "../sentry/index.ts"

async function root(): Promise<{ component: Component; withRouter: boolean }> {
  // Test builds (vite build --mode test) add pages for system tests of shared
  // components; production builds drop this branch entirely.
  if (import.meta.env.MODE === "test" && location.pathname.startsWith("/app/__fixtures/")) {
    const fixtures = {
      components: () => import("../fixtures/ComponentsFixture.vue"),
      sentry: () => import("../fixtures/SentryFixture.vue"),
    }
    const name = location.pathname.split("/")[3] as keyof typeof fixtures
    return { component: (await fixtures[name]()).default, withRouter: false }
  }
  return { component: App, withRouter: true }
}

const { component, withRouter } = await root()
const app = createApp(component)
const pinia = createPinia()
initSentry(app, pinia)
app.use(pinia)

if (withRouter) {
  const ui = useUiStore(pinia)
  router.beforeEach(() => { ui.notFound = false })
  app.use(router)
}

app.mount("#app")
