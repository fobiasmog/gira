<script setup lang="ts">
import { computed } from "vue"
import { storeToRefs } from "pinia"
import { useRoute } from "vue-router"
import AppIcon from "../ui/AppIcon.vue"
import AppMenu from "../ui/AppMenu.vue"
import { useProjectsStore } from "../../stores/projects.ts"
import { projectSections, sectionOf, type ProjectSection } from "../../router/sections.ts"
import { toneOf } from "../../styles/tones.ts"
import { t } from "../../i18n/index.ts"

const emit = defineEmits<{ navigate: [] }>()
const route = useRoute()
const { list, current } = storeToRefs(useProjectsStore())

const sections = computed(() => projectSections.filter((section) => !section.ownerOnly || current.value?.owned_by_me))
const isActive = (section: ProjectSection) => sectionOf(route.name) === section
</script>

<template>
  <nav class="side-nav" :aria-label="t('navigation.menu')" @click="(e) => (e.target as Element).closest('a') && emit('navigate')">
    <RouterLink :to="{ name: 'dashboard' }" class="logo">
      <span class="logo__mark" aria-hidden="true">G</span>
      <span>Goalner</span>
    </RouterLink>

    <AppMenu :label="t('navigation.switchProject')">
      <template #trigger="{ id, expanded }">
        <button type="button" class="switcher" :popovertarget="id" :aria-expanded="expanded">
          <template v-if="current">
            <span class="switcher__initial" :data-tone="toneOf(current.id)" aria-hidden="true">{{ current.title.charAt(0).toUpperCase() }}</span>
            <span class="switcher__text">
              <span class="visually-hidden">{{ t("navigation.switchProject") }}: </span>
              <span class="switcher__title ellipsis">{{ current.title }}</span>
              <span class="switcher__short">{{ current.short_name }}</span>
            </span>
          </template>
          <span v-else class="switcher__text switcher__title">{{ t("navigation.chooseProject") }}</span>
          <AppIcon name="expand_more" :size="20" />
        </button>
      </template>
      <template #default="{ close }">
        <RouterLink
          v-for="project in list"
          :key="project.id"
          :to="{ name: 'board', params: { pid: project.id } }"
          class="menu__item"
          :aria-current="current?.id === project.id ? 'page' : undefined"
          @click="close"
        >
          <span class="marker" :data-tone="toneOf(project.id)" />
          <span class="ellipsis">{{ project.title }}</span>
        </RouterLink>
        <hr v-if="list.length" class="menu__separator">
        <RouterLink :to="{ name: 'project-new' }" class="menu__item" @click="close">
          <AppIcon name="add" :size="20" />{{ t("navigation.newProject") }}
        </RouterLink>
      </template>
    </AppMenu>

    <ul role="list" class="side-nav__list">
      <li>
        <RouterLink :to="{ name: 'dashboard' }" class="side-nav__link" exact-active-class="is-active">
          <AppIcon name="home" :size="20" />{{ t("navigation.dashboard") }}
        </RouterLink>
      </li>
    </ul>

    <section v-if="current" class="side-nav__section" :aria-labelledby="`project-nav-${current.id}`">
      <h2 :id="`project-nav-${current.id}`" class="visually-hidden">{{ current.title }}</h2>
      <ul role="list" class="side-nav__list">
        <li v-for="section in sections" :key="section.name">
          <RouterLink
            :to="{ name: section.name, params: { pid: current.id } }"
            class="side-nav__link"
            :class="{ 'is-active': isActive(section) }"
            :aria-current="isActive(section) ? 'page' : undefined"
          >
            <AppIcon :name="section.icon" :size="20" />{{ t(section.label) }}
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
            class="side-nav__link side-nav__project"
            :class="{ 'is-current-project': current?.id === project.id }"
          >
            <span class="marker" :data-tone="toneOf(project.id)" /><span class="ellipsis">{{ project.title }}</span>
          </RouterLink>
        </li>
        <li>
          <RouterLink :to="{ name: 'project-new' }" class="side-nav__link" active-class="is-active">
            <AppIcon name="add" :size="20" />{{ t("navigation.newProject") }}
          </RouterLink>
        </li>
      </ul>
    </section>

    <div class="grow" />
    <div class="side-nav__footer">
      <slot name="footer" />
    </div>
  </nav>
</template>

<style scoped>
.side-nav {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
  min-block-size: 100%;
  padding: var(--space-4) var(--space-3);
  background: var(--color-nav-bg);
  color: var(--color-nav-text);
  font-size: var(--text-sm);
}

.logo {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  padding: var(--space-1) var(--space-2);
  border-radius: var(--radius);
  color: var(--color-nav-strong);
  font-size: var(--text-lg);
  font-weight: 700;
  text-decoration: none;

  &:hover { color: var(--color-nav-strong); }
  &:focus-visible { outline-color: var(--color-nav-text); }
}

/* Brand mark; dark letter on the brand purple, as white on it is too faint. */
.logo__mark {
  display: inline-grid;
  place-items: center;
  inline-size: 30px;
  block-size: 30px;
  border-radius: var(--radius);
  background: var(--color-main);
  color: var(--color-nav-bg);
  font-size: var(--text-md);
}

.switcher {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  inline-size: 100%;
  min-block-size: 48px;
  padding: var(--space-2);
  border: 1px solid rgb(255 255 255 / 0.08);
  border-radius: var(--radius);
  background: var(--color-nav-raised);
  color: var(--color-nav-text);
  text-align: start;

  &:hover { background: var(--color-nav-active); color: var(--color-nav-strong); }
  &:focus-visible { outline-color: var(--color-nav-text); }
}

/* AppMenu wraps the trigger in an inline anchor; let it fill the sidebar. */
.side-nav > :deep(.menu-anchor) { display: flex; }

.switcher__initial {
  display: inline-grid;
  place-items: center;
  flex: none;
  inline-size: 32px;
  block-size: 32px;
  border-radius: var(--radius);
  background: var(--tone-bg);
  color: var(--tone-text);
  font-weight: 700;
}

.switcher__text { display: grid; flex-grow: 1; min-inline-size: 0; line-height: 1.3; }
.switcher__title { color: var(--color-nav-strong); font-weight: 500; }
.switcher__short { color: var(--color-nav-muted); font-size: var(--text-xs); letter-spacing: 0.04em; }

.side-nav__section { display: grid; gap: var(--space-1); }

.side-nav__heading {
  padding-inline: var(--space-3);
  color: var(--color-nav-heading);
  font-size: var(--text-xs);
  font-weight: 500;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.side-nav__heading-link {
  border-radius: var(--radius-sm);
  color: inherit;
  text-decoration: none;

  &:hover { color: var(--color-nav-strong); text-decoration: underline; }
  &:focus-visible { outline-color: var(--color-nav-text); }
}

.side-nav__list { display: grid; gap: 2px; }

.side-nav__link {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  min-block-size: var(--target-size);
  padding: var(--space-1) var(--space-3);
  border-radius: var(--radius);
  color: var(--color-nav-text);
  text-decoration: none;

  &:hover { background: var(--color-nav-raised); color: var(--color-nav-strong); }
  &.is-active { background: var(--color-nav-active); color: var(--color-nav-strong); font-weight: 500; }
  &:focus-visible { outline-color: var(--color-nav-text); outline-offset: 0; }
}

.side-nav__project .marker { margin-inline: 5px; }
.side-nav__project.is-current-project { color: var(--color-nav-strong); font-weight: 500; }

.side-nav__footer {
  display: grid;
  padding-block-start: var(--space-3);
  border-block-start: 1px solid rgb(255 255 255 / 0.08);
}
</style>
