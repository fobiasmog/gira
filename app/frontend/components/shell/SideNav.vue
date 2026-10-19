<script setup lang="ts">
import { storeToRefs } from "pinia"
import { useRoute } from "vue-router"
import AppIcon, { type IconName } from "../ui/AppIcon.vue"
import { useProjectsStore } from "../../stores/projects.ts"
import { t, type MessageKey } from "../../i18n/index.ts"

const emit = defineEmits<{ navigate: [] }>()
const route = useRoute()
const { list, current } = storeToRefs(useProjectsStore())

interface Item { name: string; label: MessageKey; icon: IconName; also?: string[] }
const projectItems: Item[] = [
  { name: "board", label: "navigation.board", icon: "view_kanban", also: ["board-list", "task"] },
  { name: "backlog", label: "navigation.backlog", icon: "inbox" },
  { name: "sprints", label: "navigation.sprints", icon: "sprint" },
  { name: "milestones", label: "navigation.milestones", icon: "flag", also: ["milestone"] },
  { name: "members", label: "navigation.members", icon: "group" },
  { name: "archive", label: "navigation.archive", icon: "archive", also: ["archived-task"] },
]

const isActive = (item: Item) => route.name === item.name || item.also?.includes(String(route.name))
</script>

<template>
  <nav class="side-nav" :aria-label="t('navigation.menu')" @click="(e) => (e.target as Element).closest('a') && emit('navigate')">
    <RouterLink :to="{ name: 'dashboard' }" class="logo">
      <img src="/og_img.png" alt="" width="36" height="36">
      <span>Goalner</span>
    </RouterLink>

    <ul role="list" class="side-nav__list">
      <li>
        <RouterLink :to="{ name: 'dashboard' }" class="side-nav__link" exact-active-class="is-active">
          <AppIcon name="home" />{{ t("navigation.dashboard") }}
        </RouterLink>
      </li>
    </ul>

    <section v-if="current" class="side-nav__section" :aria-labelledby="`project-nav-${current.id}`">
      <h2 :id="`project-nav-${current.id}`" class="side-nav__heading ellipsis">{{ current.title }}</h2>
      <ul role="list" class="side-nav__list">
        <li v-for="item in projectItems" :key="item.name">
          <RouterLink
            :to="{ name: item.name, params: { pid: current.id } }"
            class="side-nav__link"
            :class="{ 'is-active': isActive(item) }"
            :aria-current="isActive(item) ? 'page' : undefined"
          >
            <AppIcon :name="item.icon" />{{ t(item.label) }}
          </RouterLink>
        </li>
        <li v-if="current.owned_by_me">
          <RouterLink :to="{ name: 'project-settings', params: { pid: current.id } }" class="side-nav__link" active-class="is-active">
            <AppIcon name="settings" />{{ t("navigation.projectSettings") }}
          </RouterLink>
        </li>
      </ul>
    </section>

    <section class="side-nav__section" aria-labelledby="projects-nav">
      <h2 id="projects-nav" class="side-nav__heading">
        <RouterLink :to="{ name: 'projects' }" class="side-nav__heading-link">{{ t("navigation.projects") }}</RouterLink>
      </h2>
      <ul role="list" class="side-nav__list">
        <li v-for="project in list" :key="project.id">
          <RouterLink
            :to="{ name: 'board', params: { pid: project.id } }"
            class="side-nav__link"
            :class="{ 'is-active': current?.id === project.id }"
          >
            <AppIcon name="folder_open" /><span class="ellipsis">{{ project.title }}</span>
          </RouterLink>
        </li>
        <li>
          <RouterLink :to="{ name: 'project-new' }" class="side-nav__link" active-class="is-active">
            <AppIcon name="add" />{{ t("navigation.newProject") }}
          </RouterLink>
        </li>
      </ul>
    </section>

    <div class="grow" />
    <slot name="footer" />
  </nav>
</template>

<style scoped>
.side-nav {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
  min-block-size: 100%;
  padding: var(--space-3);
  background: linear-gradient(180deg, var(--color-main) 0%, var(--color-main-dark) 100%);
  color: #fff;
}

.logo {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  padding: var(--space-2);
  color: #fff;
  font-size: var(--text-lg);
  font-weight: 700;
  text-decoration: none;

  &:hover { color: #fff; }
}

.side-nav__section { display: grid; gap: var(--space-1); }

.side-nav__heading {
  padding-inline: var(--space-3);
  font-size: var(--text-xs);
  font-weight: 500;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  opacity: 0.85;
}

.side-nav__heading-link {
  color: inherit;
  text-decoration: none;

  &:hover { color: inherit; text-decoration: underline; }
}

.side-nav__list { display: grid; gap: 2px; }

.side-nav__link {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  min-block-size: var(--target-size);
  padding: var(--space-1) var(--space-3);
  border-radius: var(--radius);
  color: #fff;
  text-decoration: none;

  &:hover { background: rgb(255 255 255 / 0.12); color: #fff; }
  &.is-active { background: rgb(255 255 255 / 0.2); font-weight: 500; }
  &:focus-visible { outline-color: #fff; }
}
</style>
