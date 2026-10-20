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
import { calendarDaysFrom, formatDateTime, formatDayTile, formatLongDate } from "../i18n/format.ts"
import { toneOf } from "../styles/tones.ts"

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

const today = new Date()
const projectTitles = computed(() => new Map(projects.list.map((project) => [project.id, project.title])))
const openCount = (group: (typeof overview.value)[number]) => group.columns.reduce((sum, column) => sum + column.tasks.length, 0)
const deadlineTiles = computed(() => deadlines.value.map((task) => ({
  task,
  today: calendarDaysFrom(today, new Date(task.deadline)) === 0,
  ...formatDayTile(language.value, task.deadline),
})))

function showTasksOf(event: Event) {
  const value = (event.target as HTMLSelectElement).value
  void router.replace({ name: "dashboard", query: value ? { user: value } : {} })
}
</script>

<template>
  <section v-if="loaded" class="page dashboard">
    <header class="dashboard__header">
      <div class="dashboard__heading">
        <p class="dashboard__date">{{ formatLongDate(language, today) }}</p>
        <h1>{{ teammate ? t("dashboard.tasksOf", { name: teammate.name }) : t("dashboard.myTasks") }}</h1>
      </div>
      <label v-if="teammates.length" class="dashboard__person">
        {{ t("dashboard.showTasksOf") }}
        <select class="input" :value="userId ?? ''" @change="showTasksOf">
          <option value="">{{ t("dashboard.me") }}</option>
          <option v-for="person in teammates.filter((p) => p.id !== profile?.id)" :key="person.id" :value="person.id">{{ person.name }}</option>
        </select>
      </label>
    </header>

    <div class="dashboard__grid">
      <section class="dashboard__projects" aria-labelledby="dashboard-tasks">
        <h2 id="dashboard-tasks" class="visually-hidden">{{ t("dashboard.myTasks") }}</h2>
        <article v-for="group in overview" :key="group.project.id" class="panel dashboard__project" :aria-labelledby="`dashboard-project-${group.project.id}`">
          <header class="project-card__header">
            <span class="marker" :data-tone="toneOf(group.project.id)" />
            <h3 :id="`dashboard-project-${group.project.id}`" class="ellipsis">{{ group.project.title }}</h3>
            <span class="badge">
              <span aria-hidden="true">{{ openCount(group) }}</span><span class="visually-hidden">{{ tc("board.taskCount", openCount(group)) }}</span>
            </span>
            <span class="grow" />
            <RouterLink :to="{ name: 'board', params: { pid: group.project.id } }" class="project-card__open">
              {{ t("dashboard.openBoard") }}<span class="visually-hidden">: {{ group.project.title }}</span><AppIcon name="chevron_right" :size="18" />
            </RouterLink>
          </header>
          <div class="project-card__columns">
            <section v-for="column in group.columns" :key="column.id" class="column-group">
              <h4 class="column-group__title">{{ column.title }} · {{ tc("board.taskCount", column.tasks.length) }}</h4>
              <ul role="list" class="column-group__tasks">
                <li v-for="task in column.tasks" :key="task.id" class="tile">
                  <span class="tile__top">
                    <span class="tile__key">{{ task.key }}</span>
                    <span v-if="task.important" class="tile__important" :title="t('board.important')">
                      <AppIcon name="local_fire_department_filled" :size="16" /><span class="visually-hidden">{{ t("board.important") }}</span>
                    </span>
                  </span>
                  <RouterLink class="tile__title break-word" :to="{ name: 'task', params: { pid: group.project.id, ref: task.key } }">{{ task.title }}</RouterLink>
                </li>
              </ul>
            </section>
          </div>
        </article>
        <p v-if="!overview.length" class="empty-state panel">
          {{ projects.list.length ? t("dashboard.noTasks") : t("dashboard.noProjects") }}
        </p>
      </section>

      <aside class="panel dashboard__deadlines" aria-labelledby="dashboard-deadlines">
        <h2 id="dashboard-deadlines" class="section-title">{{ t("dashboard.deadlines") }}</h2>
        <ul v-if="deadlineTiles.length" role="list" class="deadlines">
          <li v-for="{ task, today: isToday, weekday, day } in deadlineTiles" :key="task.id" class="deadline" :class="{ 'deadline--today': isToday }">
            <time class="deadline__date" :datetime="task.deadline" :title="formatDateTime(language, task.deadline)">
              <span class="deadline__weekday">{{ isToday ? t("dashboard.today") : weekday }}</span>
              <span class="deadline__day">{{ day }}</span>
            </time>
            <span class="deadline__text">
              <span class="deadline__meta ellipsis">{{ task.key }}<template v-if="projectTitles.get(task.project_id)"> · {{ projectTitles.get(task.project_id) }}</template></span>
              <RouterLink class="deadline__title break-word" :to="{ name: 'task', params: { pid: task.project_id, ref: task.key } }">{{ task.title }}</RouterLink>
            </span>
          </li>
        </ul>
        <p v-else class="muted small">{{ t("dashboard.noDeadlines") }}</p>
      </aside>
    </div>
  </section>
</template>

<style scoped>
.dashboard { max-inline-size: 1240px; gap: var(--space-4); }

.dashboard__header {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-end;
  justify-content: space-between;
  gap: var(--space-3) var(--space-5);
}

.dashboard__heading { display: grid; gap: var(--space-1); }
.dashboard__date { color: var(--color-muted); font-size: var(--text-sm); }
.dashboard__date::first-letter { text-transform: uppercase; }

.dashboard__person {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-2);
  color: var(--color-muted);
  font-size: var(--text-sm);
}

.dashboard__person .input { inline-size: auto; min-inline-size: 10rem; color: var(--color-text); }

.dashboard__grid {
  display: grid;
  gap: var(--space-4);
  align-items: start;
}

@media (min-width: 1100px) {
  .dashboard__grid { grid-template-columns: minmax(0, 1fr) 320px; }
}

.dashboard__projects { display: grid; gap: var(--space-4); }
.dashboard__project { display: grid; gap: var(--space-4); padding: var(--space-4) var(--space-5) var(--space-5); }

.project-card__header { display: flex; align-items: center; gap: var(--space-2); min-inline-size: 0; }
.project-card__header h3 { min-inline-size: 0; font-size: var(--text-md); }

.project-card__open {
  display: inline-flex;
  flex: none;
  align-items: center;
  gap: 2px;
  border-radius: var(--radius-sm);
  color: var(--color-primary);
  font-size: var(--text-sm);
  font-weight: 500;
  text-decoration: none;

  &:hover { color: var(--color-primary-hover); text-decoration: underline; }
}

.project-card__columns {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  gap: var(--space-4);
}

.column-group { display: grid; align-content: start; gap: var(--space-2); }

.column-group__title {
  color: var(--color-muted);
  font-size: var(--text-xs);
  font-weight: 500;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}

.column-group__tasks { display: grid; gap: var(--space-2); }

.tile {
  display: grid;
  gap: 2px;
  padding: var(--space-2) var(--space-3);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  background: var(--color-surface-raised);
}

.tile__top { display: flex; align-items: center; justify-content: space-between; gap: var(--space-2); }
.tile__key { color: var(--color-muted); font-size: var(--text-xs); font-weight: 500; }
.tile__important { display: inline-flex; color: var(--color-important); }

.tile__title {
  border-radius: var(--radius-sm);
  color: var(--color-text);
  font-size: var(--text-sm);
  text-decoration: none;

  &:hover { color: var(--color-primary); text-decoration: underline; }
}

.dashboard__deadlines { display: grid; gap: var(--space-3); padding: var(--space-4) var(--space-5) var(--space-5); }
.deadlines { display: grid; gap: var(--space-3); }

.deadline { display: flex; align-items: center; gap: var(--space-3); }

.deadline__date {
  display: grid;
  flex: none;
  place-items: center;
  align-content: center;
  inline-size: 52px;
  block-size: 52px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  background: var(--color-surface-raised);
  line-height: 1.15;
}

.deadline__weekday { color: var(--color-muted); font-size: var(--text-xs); text-transform: capitalize; }
.deadline__day { font-size: var(--text-lg); font-weight: 500; }

.deadline--today .deadline__date { border-color: var(--color-primary); background: var(--color-primary); color: #fff; }
.deadline--today .deadline__weekday { color: #fff; font-size: 0.6875rem; font-weight: 500; }

.deadline__text { display: grid; min-inline-size: 0; }
.deadline__meta { color: var(--color-muted); font-size: var(--text-xs); }

.deadline__title {
  border-radius: var(--radius-sm);
  color: var(--color-text);
  font-size: var(--text-sm);
  font-weight: 500;
  text-decoration: none;

  &:hover { color: var(--color-primary); text-decoration: underline; }
}
</style>
