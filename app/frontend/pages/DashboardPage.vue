<script setup lang="ts">
import { computed, ref, watch } from "vue"
import { storeToRefs } from "pinia"
import { useRoute, useRouter } from "vue-router"
import AppIcon from "../components/ui/AppIcon.vue"
import { useMeStore } from "../stores/me.ts"
import { useProjectsStore } from "../stores/projects.ts"
import { useStatisticsStore } from "../stores/statistics.ts"
import { useUiStore } from "../stores/ui.ts"
import { parseId } from "../router/routes.ts"
import { language, t, tc } from "../i18n/index.ts"
import { formatRelativeDay } from "../i18n/format.ts"

// The signed-in user's open tasks and upcoming deadlines, or a teammate's
// (?user=<id>), across the projects both of them belong to.
const route = useRoute()
const router = useRouter()
const statistics = useStatisticsStore()
const { overview, deadlines, teammates } = storeToRefs(statistics)
const { profile } = storeToRefs(useMeStore())
const projects = useProjectsStore()
const ui = useUiStore()
const loaded = ref(false)

const userId = computed(() => parseId(route.query.user))
const teammate = computed(() => teammates.value.find((person) => person.id === userId.value) ?? null)

watch(userId, async (id) => {
  const ok = await ui.load(statistics.load(id ?? undefined).then(() => true))
  loaded.value = !!ok
}, { immediate: true })

function showTasksOf(event: Event) {
  const value = (event.target as HTMLSelectElement).value
  void router.replace({ name: "dashboard", query: value ? { user: value } : {} })
}
</script>

<template>
  <section v-if="loaded" class="page dashboard">
    <header class="page__header">
      <h1 class="grow">{{ teammate ? t("dashboard.tasksOf", { name: teammate.name }) : t("dashboard.myTasks") }}</h1>
      <label v-if="teammates.length" class="row small">
        {{ t("dashboard.showTasksOf") }}
        <select class="input" :value="userId ?? ''" @change="showTasksOf">
          <option value="">{{ t("dashboard.me") }}</option>
          <option v-for="person in teammates.filter((p) => p.id !== profile?.id)" :key="person.id" :value="person.id">{{ person.name }}</option>
        </select>
      </label>
    </header>

    <div class="dashboard__grid">
      <section class="stack" aria-labelledby="dashboard-tasks">
        <h2 id="dashboard-tasks" class="visually-hidden">{{ t("dashboard.myTasks") }}</h2>
        <article v-for="group in overview" :key="group.project.id" class="panel dashboard__project">
          <h3>
            <RouterLink :to="{ name: 'board', params: { pid: group.project.id } }">{{ group.project.title }}</RouterLink>
          </h3>
          <section v-for="column in group.columns" :key="column.id ?? 'backlog'" class="stack dashboard__column">
            <h4 class="small muted">{{ column.title ?? t("dashboard.backlog") }} · {{ tc("board.taskCount", column.tasks.length) }}</h4>
            <ul role="list" class="stack">
              <li v-for="task in column.tasks" :key="task.id" class="row">
                <AppIcon v-if="task.important" name="local_fire_department_filled" :size="18" class="important" />
                <span class="small muted">{{ task.key }}</span>
                <RouterLink class="break-word" :to="{ name: 'task', params: { pid: group.project.id, ref: task.key } }">{{ task.title }}</RouterLink>
              </li>
            </ul>
          </section>
        </article>
        <p v-if="!overview.length" class="empty-state panel">
          {{ projects.list.length ? t("dashboard.noTasks") : t("dashboard.noProjects") }}
        </p>
      </section>

      <aside class="panel stack dashboard__deadlines" aria-labelledby="dashboard-deadlines">
        <h2 id="dashboard-deadlines">{{ t("dashboard.deadlines") }}</h2>
        <ul v-if="deadlines.length" role="list" class="stack">
          <li v-for="task in deadlines" :key="task.id" class="deadline">
            <time class="small" :datetime="task.deadline">{{ formatRelativeDay(language, task.deadline) }}</time>
            <RouterLink class="break-word" :to="{ name: 'task', params: { pid: task.project_id, ref: task.key } }">
              <span class="muted">{{ task.key }}</span> {{ task.title }}
            </RouterLink>
          </li>
        </ul>
        <p v-else class="muted">{{ t("dashboard.noDeadlines") }}</p>
      </aside>
    </div>
  </section>
</template>

<style scoped>
.dashboard { max-inline-size: 1200px; }

.dashboard__grid {
  display: grid;
  gap: var(--space-4);
  align-items: start;
}

@media (min-width: 1000px) {
  .dashboard__grid { grid-template-columns: minmax(0, 1fr) 320px; }
}

.dashboard__project { display: grid; gap: var(--space-3); padding: var(--space-4); }
.dashboard__project h3 a { color: var(--color-text); text-decoration: none; }
.dashboard__column h4 { text-transform: uppercase; letter-spacing: 0.04em; }
.dashboard__deadlines { padding: var(--space-4); }
.deadline { display: grid; gap: 2px; }
.important { color: var(--color-accent-dark); }
</style>
