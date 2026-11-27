<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from "vue"
import { storeToRefs } from "pinia"
import { useRouter } from "vue-router"
import AppField from "../components/ui/AppField.vue"
import AppIcon, { type IconName } from "../components/ui/AppIcon.vue"
import AppTextarea from "../components/ui/AppTextarea.vue"
import MarkdownView from "../components/MarkdownView.vue"
import CommentItem from "../components/task/CommentItem.vue"
import CommentForm from "../components/task/CommentForm.vue"
import ArchiveChangeDialog from "../components/changes/ArchiveChangeDialog.vue"
import { phaseName } from "../components/changes/PhasePill.vue"
import WaitingMarker from "../components/changes/WaitingMarker.vue"
import ChangeWorkspace from "../components/changes/ChangeWorkspace.vue"
import { agentOption, historyText, statusText } from "../components/changes/requestTexts.ts"
import { changesApi, type ChangeFields } from "../api/changes.ts"
import { activeAgents, agentsApi } from "../api/agents.ts"
import { tasksApi } from "../api/tasks.ts"
import { ApiError } from "../api/client.ts"
import { CHANGE_PHASES, type ChangeDetail, type ChangeEvent, type Comment, type ProjectAgent } from "../api/types.ts"
import {
  asksForReply, boardProgress, canAskStep, nextStep, refresher, statusLine, threadEntries, unfinished,
} from "../composables/changes.ts"
import { boardLocation, changeLocation } from "../router/routes.ts"
import { OTHER_TAB, useBoardStore } from "../stores/board.ts"
import { useMeStore } from "../stores/me.ts"
import { useUiStore } from "../stores/ui.ts"
import { language, t } from "../i18n/index.ts"
import { personName } from "../i18n/people.ts"
import { formatDate, formatDateTime } from "../i18n/format.ts"

// A change's page (spec web-client, "Change page" and "Requests on the
// change page"): its phases, its open request and agent with their actions,
// the button for the next step, its idea, its thread with its history, and
// the OpenSpec files of its last import. Phases move with the steps agents
// take, and through the API; the page offers no phase menu. While a request is
// open the page reloads the change, its thread and the agents. An archived
// change's page is read-only.
const props = defineProps<{ projectId: number; changeRef: string }>()
const router = useRouter()
const ui = useUiStore()
const board = useBoardStore()
const { profile } = storeToRefs(useMeStore())

const TASKS_MD = "tasks.md"

const change = ref<ChangeDetail | null>(null)
const comments = ref<Comment[]>([])
// The project's active agents with their states.
const agents = ref<ProjectAgent[]>([])
const missing = ref(false)
const loaded = ref(false)
const editingIdea = ref(false)
// The texts of the files shown so far, by path, and whether the file is
// shown as its source.
const fileTexts = ref(new Map<string, string>())
const source = ref(false)

watch(() => [props.projectId, props.changeRef] as const, async ([projectId, changeRef]) => {
  loaded.value = false
  missing.value = false
  change.value = null
  editingIdea.value = false
  fileTexts.value = new Map()
  source.value = false
  // The board store has the columns that tell which cards are done.
  const ready = await ui.load(board.projectId === projectId ? Promise.resolve(true) : board.load(projectId, OTHER_TAB).then(() => true))
  if (!ready) return
  try {
    const [detail, thread, listed] = await Promise.all([
      changesApi.show(projectId, changeRef), changesApi.comments(projectId, changeRef), agentsApi.inProject(projectId),
    ])
    if (projectId !== props.projectId || changeRef !== props.changeRef) return
    change.value = detail
    comments.value = thread
    agents.value = activeAgents(listed)
  } catch (error) {
    if (error instanceof ApiError && error.status === 404) missing.value = true
    else ui.fail(error)
  }
  loaded.value = true
}, { immediate: true })

const isOpen = computed(() => change.value?.archived_at === null)
const progress = computed(() => boardProgress(board.columns, change.value?.cards ?? []))

// Idea, Exploring, Proposed, Implementing and Done: those before the
// current one are passed.
const steps = computed(() => {
  const current = CHANGE_PHASES.indexOf(change.value?.phase ?? "idea")
  return CHANGE_PHASES.map((phase, index) => ({ phase, passed: index < current, current: index === current }))
})

// The board's tabs follow the phase, the waiting marker, the request and the agent.
function syncBoard(detail: ChangeDetail) {
  if (board.projectId !== props.projectId) return
  board.changes = board.changes.map((listed) => listed.id === detail.id
    ? { ...listed, phase: detail.phase, waiting_for_people: detail.waiting_for_people, request: detail.request, agent: detail.agent }
    : listed)
}

async function update(fields: ChangeFields): Promise<ChangeDetail> {
  const updated = await changesApi.update(props.projectId, change.value!.id, fields)
  change.value = updated
  syncBoard(updated)
  return updated
}

async function refresh() {
  try {
    const detail = await changesApi.show(props.projectId, change.value!.id)
    change.value = detail
    syncBoard(detail)
  } catch (error) {
    ui.fail(error)
  }
}

// Requests and the agent (spec web-client, "Requests on the change page")

const agentsById = computed(() => new Map(agents.value.map((agent) => [agent.id, agent])))
const status = computed(() => (change.value ? statusLine(change.value, agentsById.value) : null))
const askable = computed(() => (change.value && canAskStep(change.value) ? nextStep(change.value.phase) : null))
const agentOn = computed(() => (change.value?.agent?.on ? change.value.agent.user : null))

const replyNote = computed(() => {
  const detail = change.value
  if (!detail || !asksForReply(detail)) return null
  return detail.agent ? t("changePage.replyNote", { name: detail.agent.user.name }) : t("changePage.replyNoteAny")
})

// The comment field's text goes with the request as its comment.
// The comment field's text, which the button for the next step sends along.
const draft = ref("")
const asking = ref(false)

async function askStep() {
  const next = askable.value
  if (!next || asking.value) return
  const label = t(`changePage.steps.${next.label}`)
  asking.value = true
  try {
    await changesApi.askStep(props.projectId, change.value!.id, next.kind, draft.value)
    draft.value = ""
    ui.toast(t("changePage.stepAsked", { step: label }))
    await reload()
  } catch (error) {
    ui.fail(error)
  } finally {
    asking.value = false
  }
}

// The change, its thread and the agents' states, as they are now.
async function reload() {
  const current = change.value
  if (!current) return
  try {
    const [detail, thread, listed] = await Promise.all([
      changesApi.show(props.projectId, current.id), changesApi.comments(props.projectId, current.id), agentsApi.inProject(props.projectId),
    ])
    if (change.value?.id !== current.id) return
    change.value = detail
    comments.value = thread
    agents.value = activeAgents(listed)
    syncBoard(detail)
  } catch (error) {
    ui.fail(error)
  }
}

// While the change has an open request, so that its state, the agent's
// comments and the phase show up without reloading the page.
const autoRefresh = refresher(reload)
watch(() => Boolean(change.value && isOpen.value && change.value.request), (open) => autoRefresh.set(open), { immediate: true })
onBeforeUnmount(() => autoRefresh.set(false))

async function cancelRequest() {
  const request = change.value?.request
  if (!request) return
  try {
    await changesApi.cancelRequest(props.projectId, request.id)
    ui.toast(t("changePage.requestCancelled"))
    await reload()
  } catch (error) {
    ui.fail(error)
  }
}

async function release() {
  const agent = agentOn.value
  if (!agent) return
  try {
    const detail = await changesApi.releaseAgent(props.projectId, change.value!.id)
    change.value = detail
    syncBoard(detail)
    ui.toast(t("changePage.released", { name: agent.name }))
    await reload()
  } catch (error) {
    ui.fail(error)
  }
}

async function pickAgent(event: Event) {
  const select = event.target as HTMLSelectElement
  const agent = select.value ? Number(select.value) : null
  try {
    const updated = await update({ agent })
    ui.toast(updated.agent ? t("changePage.agentPicked", { name: updated.agent.user.name }) : t("changePage.anyAgentPicked"))
  } catch (error) {
    select.value = String(change.value?.agent?.user.id ?? "")
    ui.fail(error)
  }
}

// Idea, editable while the change is in Idea

const ideaDraft = ref("")
const ideaErrors = ref<string[]>([])
const savingIdea = ref(false)
const ideaEditable = computed(() => isOpen.value && change.value?.phase === "idea")

function editIdea() {
  ideaDraft.value = change.value?.idea ?? ""
  ideaErrors.value = []
  editingIdea.value = true
}

async function saveIdea() {
  savingIdea.value = true
  ideaErrors.value = []
  try {
    await update({ idea: ideaDraft.value.trim() ? ideaDraft.value : null })
    editingIdea.value = false
  } catch (error) {
    if (error instanceof ApiError && error.status === 422) ideaErrors.value = Object.values(error.fields).flat()
    else ui.fail(error)
  } finally {
    savingIdea.value = false
  }
}

// Thread

const entries = computed(() => threadEntries(comments.value, change.value?.history ?? []))

const EVENT_ICONS: Record<ChangeEvent["kind"], IconName> = { phase: "flag", import: "description", request: "robot", release: "logout", block: "close" }

const eventKey = (at: number, event: ChangeEvent) => `event-${at}-${event.kind}-${event.phase}-${event.step}-${event.state}`

// A reply can end the wait for people.
async function postComment(body: string, files: File[]) {
  const comment = await changesApi.addComment(props.projectId, change.value!.id, body, files)
  comments.value = [...comments.value, comment]
  await refresh()
}

async function saveComment(comment: Comment, body: string) {
  try {
    const updated = await tasksApi.updateComment(comment.id, body)
    comments.value = comments.value.map((c) => (c.id === updated.id ? updated : c))
  } catch (error) {
    ui.fail(error)
    throw error
  }
}

async function removeComment(comment: Comment) {
  try {
    await tasksApi.deleteComment(comment.id)
    comments.value = comments.value.filter((c) => c.id !== comment.id)
    await refresh()
  } catch (error) {
    ui.fail(error)
  }
}

// Files: one tab per file of the last import, and tasks.md. A file is
// loaded when its tab is first shown.

const fileTabs = computed(() => {
  const detail = change.value
  if (!detail) return []
  return [...detail.files.map((file) => file.path), ...(detail.tasks_text === null ? [] : [TASKS_MD])]
})
const selectedFile = ref<string | null>(null)

watch(fileTabs, (paths) => {
  if (!selectedFile.value || !paths.includes(selectedFile.value)) selectedFile.value = paths[0] ?? null
}, { immediate: true })

watch(selectedFile, async (path) => {
  const detail = change.value
  if (!detail || !path || path === TASKS_MD || fileTexts.value.has(path)) return
  try {
    const file = await changesApi.file(props.projectId, detail.id, path)
    fileTexts.value = new Map(fileTexts.value).set(path, file.text)
  } catch (error) {
    ui.fail(error)
  }
})

const selectedText = computed(() => {
  const path = selectedFile.value
  if (!path) return null
  return path === TASKS_MD ? change.value?.tasks_text ?? null : fileTexts.value.get(path) ?? null
})

const fileTabId = (path: string) => `change-file-tab-${path.replace(/[^a-z0-9]+/gi, "-")}`

function onFileKey(event: KeyboardEvent) {
  const index = fileTabs.value.indexOf(selectedFile.value ?? "")
  const last = fileTabs.value.length - 1
  const target = ({ ArrowRight: index + 1, ArrowLeft: index - 1, Home: 0, End: last } as Record<string, number>)[event.key]
  if (target === undefined || index === -1) return
  event.preventDefault()
  const path = fileTabs.value[(target + fileTabs.value.length) % fileTabs.value.length]!
  selectedFile.value = path
  document.getElementById(fileTabId(path))?.focus()
}

// Archive

const archiving = ref(false)

async function archive() {
  const current = change.value!
  const archived = board.projectId === props.projectId
    ? await board.archiveChange(current.id)
    : await changesApi.archive(props.projectId, current.id)
  ui.toast(t("changes.archived", { name: current.name }))
  await router.replace(changeLocation(props.projectId, archived))
}
</script>

<template>
  <p v-if="loaded && missing" class="page notice" role="status">{{ t("changePage.missing", { name: changeRef }) }}</p>

  <article v-else-if="loaded && change" class="page page--full change-page">
    <header class="change-header panel">
      <div class="change-header__title">
        <p class="small">
          <RouterLink :to="{ name: 'changes', params: { pid: projectId } }" class="row"><AppIcon name="chevron_left" :size="18" />{{ t("changes.title") }}</RouterLink>
        </p>
        <h1 class="break-word">{{ change.name }}</h1>
        <ol role="list" class="phase-steps" :aria-label="t('changePage.phases')">
          <li
            v-for="step in steps"
            :key="step.phase"
            class="phase-steps__step"
            :class="{ 'phase-steps__step--passed': step.passed, 'phase-steps__step--current': step.current }"
            :aria-current="step.current ? 'step' : undefined"
          >
            <AppIcon v-if="step.passed" name="check_circle" :size="14" />
            {{ phaseName(step.phase) }}
            <span v-if="step.passed" class="visually-hidden">({{ t("changePage.passed") }})</span>
            <span v-if="step.current" class="visually-hidden">({{ t("changePage.current") }})</span>
          </li>
        </ol>
        <p class="small muted change-header__meta">
          <span>{{ t("changePage.progress", { done: progress.done, total: progress.total }) }}</span>
          <span>{{ t("changePage.baseBranch", { branch: change.base_branch }) }}</span>
          <RouterLink v-if="isOpen" :to="boardLocation(projectId, 'kanban', { kind: 'change', name: change.name })">{{ t("changePage.openBoard") }}</RouterLink>
        </p>
      </div>

      <div v-if="isOpen" class="change-header__actions">
        <span v-if="change.waiting_for_people" class="waiting-status"><WaitingMarker />{{ t("changes.waiting") }}</span>
        <button type="button" class="button button--text" @click="archiving = true">
          <AppIcon name="archive" :size="20" />{{ t("changes.archive") }}
        </button>
      </div>
      <p v-else class="notice row change-header__archived">
        <AppIcon name="archive" :size="20" />{{ t("changePage.archivedNotice", { date: formatDate(language, change.archived_at!) }) }}
      </p>
    </header>

    <section v-if="isOpen" class="change-request panel" aria-labelledby="change-request">
      <h2 id="change-request" class="visually-hidden">{{ t("changePage.request") }}</h2>
      <div class="change-request__status grow">
        <AppIcon name="robot" :size="20" />
        <p v-if="status" role="status">{{ statusText(status) }}</p>
        <!-- While no agent is on the change: who will take its next request. -->
        <p v-else class="change-request__pick">
          <label>
            <span class="visually-hidden">{{ t("changes.agent") }}</span>
            <select class="input" :value="String(change.agent?.user.id ?? '')" @change="pickAgent">
              <option value="">{{ t("changes.anyAgent") }}</option>
              <option v-for="candidate in agents" :key="candidate.id" :value="String(candidate.id)">{{ agentOption(candidate) }}</option>
            </select>
          </label>
          {{ t("changePage.willTakeIt") }}
        </p>
      </div>
      <div class="change-request__actions">
        <template v-if="askable">
          <button type="button" class="button" :disabled="asking" @click="askStep">{{ t(`changePage.steps.${askable.label}`) }}</button>
          <span v-if="draft.trim()" class="small muted">{{ t("changePage.stepWithComment") }}</span>
        </template>
        <button v-if="change.request" type="button" class="button button--secondary" @click="cancelRequest">{{ t("changePage.cancelRequest") }}</button>
        <button v-if="agentOn" type="button" class="button button--secondary" @click="release">{{ t("changePage.release", { name: agentOn.name }) }}</button>
      </div>
    </section>

    <ChangeWorkspace v-if="change.workspace" :workspace="change.workspace" />

    <div class="change-page__main panel">
      <section class="change-section" aria-labelledby="change-idea">
        <div class="row">
          <h2 id="change-idea" class="section-title grow">{{ t("changePage.idea") }}</h2>
          <button v-if="ideaEditable && !editingIdea" type="button" class="icon-button" :aria-label="t('changePage.editIdea')" @click="editIdea">
            <AppIcon name="edit" :size="20" />
          </button>
        </div>
        <form v-if="editingIdea" class="stack" @submit.prevent="saveIdea">
          <AppField :label="t('changePage.idea')" :hint="t('changes.ideaHint')" :errors="ideaErrors" hide-label>
            <template #default="{ control }">
              <AppTextarea v-model="ideaDraft" v-bind="control" />
            </template>
          </AppField>
          <div class="row">
            <button type="submit" class="button" :disabled="savingIdea">{{ t("common.save") }}</button>
            <button type="button" class="button button--text" @click="editingIdea = false">{{ t("common.cancel") }}</button>
          </div>
        </form>
        <MarkdownView v-else-if="change.idea" :source="change.idea" class="change-idea" />
        <p v-else class="muted small">{{ t("changePage.noIdea") }}</p>
      </section>

      <section class="change-section" aria-labelledby="change-thread">
        <h2 id="change-thread" class="section-title">
          {{ t("changePage.thread") }} <span v-if="comments.length" class="badge">{{ comments.length }}</span>
        </h2>
        <ol v-if="entries.length" role="list" class="thread">
          <template v-for="entry in entries" :key="entry.kind === 'comment' ? `comment-${entry.comment.id}` : eventKey(entry.at, entry.event)">
            <CommentItem
              v-if="entry.kind === 'comment'"
              :comment="entry.comment"
              :editable="isOpen && entry.comment.author.id === profile?.id"
              :save="(body: string) => saveComment(entry.comment, body)"
              :remove="() => removeComment(entry.comment)"
            />
            <li v-else class="thread-event">
              <AppIcon :name="EVENT_ICONS[entry.event.kind]" :size="16" />
              <span>
                {{ historyText(entry.event) }}
                <time :datetime="entry.event.created_at" class="thread-event__time">· {{ formatDateTime(language, entry.event.created_at) }}</time>
              </span>
            </li>
          </template>
        </ol>
        <p v-else class="muted small">{{ t("changePage.noComments") }}</p>
        <CommentForm v-if="isOpen" v-model:body="draft" :post="postComment" :note="replyNote" />
      </section>
    </div>

    <aside class="change-page__aside panel" aria-labelledby="change-files">
      <h2 id="change-files" class="section-title">{{ t("changePage.files") }}</h2>
      <template v-if="fileTabs.length">
        <div class="row row--wrap change-files__bar">
          <div role="tablist" :aria-label="t('changePage.files')" class="change-files__tabs grow" @keydown="onFileKey">
            <button
              v-for="path in fileTabs"
              :id="fileTabId(path)"
              :key="path"
              type="button"
              role="tab"
              class="change-files__tab"
              :aria-selected="selectedFile === path ? 'true' : 'false'"
              aria-controls="change-file-panel"
              :tabindex="selectedFile === path ? 0 : -1"
              @click="selectedFile = path"
            >
              {{ path }}
            </button>
          </div>
          <button type="button" class="button button--text change-files__source" :aria-pressed="source ? 'true' : 'false'" @click="source = !source">
            <AppIcon name="code" :size="18" />{{ t("changePage.source") }}
          </button>
        </div>
        <div
          id="change-file-panel"
          role="tabpanel"
          class="change-file"
          :aria-labelledby="selectedFile ? fileTabId(selectedFile) : undefined"
          tabindex="0"
        >
          <template v-if="selectedText !== null">
            <pre v-if="source" class="change-file__source">{{ selectedText }}</pre>
            <MarkdownView v-else :source="selectedText" />
          </template>
          <p v-else class="muted small">{{ t("common.loading") }}</p>
        </div>
        <p v-if="change.imported_by && change.imported_at" class="small muted">
          {{ t("changePage.imported", { name: personName(change.imported_by), date: formatDateTime(language, change.imported_at) }) }}
        </p>
      </template>
      <p v-else class="muted small">{{ t("changePage.noFiles") }}</p>
    </aside>

    <ArchiveChangeDialog v-model:open="archiving" :change="change" :unfinished="unfinished(progress)" :on-confirm="archive" />
  </article>
</template>

<style scoped>
.change-page {
  grid-template-columns: minmax(0, 1fr);
  align-items: start;
  gap: var(--space-4);
  max-inline-size: 1240px;
}

.change-header,
.change-request { grid-column: 1 / -1; }

.change-request {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-2) var(--space-4);
  padding: var(--space-3) var(--space-5);
}

.change-request__status { display: flex; align-items: center; gap: var(--space-2); min-inline-size: 12rem; }
.change-request__actions { display: flex; flex-wrap: wrap; align-items: center; gap: var(--space-2) var(--space-3); }
.change-request__pick { display: flex; flex-wrap: wrap; align-items: center; gap: var(--space-2); }
.change-request__pick select { inline-size: auto; max-inline-size: 20rem; }

@media (min-width: 1100px) {
  .change-page { grid-template-columns: minmax(0, 1fr) minmax(0, 1.1fr); }
  .change-page__aside { position: sticky; top: var(--space-4); }
}

.change-header {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-start;
  gap: var(--space-4) var(--space-5);
  padding: var(--space-5);
}

.change-header__title { display: grid; flex: 1 1 20rem; gap: var(--space-3); min-inline-size: 0; }
.change-header__meta { display: flex; flex-wrap: wrap; gap: var(--space-1) var(--space-3); }

.change-header__actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: flex-end;
  gap: var(--space-2) var(--space-3);
}

.change-header__archived { flex: 1 1 20rem; }

.waiting-status {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 2px var(--space-2);
  border-radius: 999px;
  background: var(--tone-3-bg);
  color: var(--tone-3-text);
  font-size: var(--text-xs);
  font-weight: 500;
  white-space: nowrap;
}

/* The phases in order; passed ones carry a check, the current one is filled. */
.phase-steps { display: flex; flex-wrap: wrap; gap: 6px; }

.phase-steps__step {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px var(--space-3);
  border: 1px solid var(--color-border);
  border-radius: 999px;
  color: var(--color-muted);
  font-size: var(--text-xs);
}

.phase-steps__step--passed { border-color: transparent; background: var(--color-main-lighter); color: var(--color-main-darker); }
.phase-steps__step--current { border-color: transparent; background: var(--color-primary); color: #fff; font-weight: 500; }

.change-page__main,
.change-page__aside {
  display: grid;
  gap: var(--space-6);
  min-inline-size: 0;
  padding: var(--space-5);
}

.change-page__aside { gap: var(--space-3); }

@media (max-width: 600px) {
  .change-header,
  .change-page__main,
  .change-page__aside { padding: var(--space-4); }
}

.change-section { display: grid; gap: var(--space-3); }

.change-idea {
  padding: var(--space-3) var(--space-4);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  background: var(--color-surface-raised);
}

.thread { display: grid; gap: var(--space-4); }

.thread-event {
  display: flex;
  align-items: baseline;
  gap: var(--space-2);
  padding-inline-start: var(--space-2);
  color: var(--color-muted);
  font-size: var(--text-sm);

  .icon { align-self: center; }
}

.thread-event__time { white-space: nowrap; }

.change-files__bar { align-items: flex-end; }
.change-files__tabs { display: flex; flex-wrap: wrap; gap: var(--space-1); min-inline-size: 0; }

.change-files__tab {
  min-block-size: 32px;
  padding: var(--space-1) var(--space-2);
  border: 1px solid transparent;
  border-radius: var(--radius-sm);
  background: none;
  color: var(--color-muted);
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  overflow-wrap: anywhere;
  text-align: start;

  &:hover { color: var(--color-text); background: var(--color-main-tint); }
  &[aria-selected="true"] { background: var(--color-main-lighter); color: var(--color-main-darker); font-weight: 500; }
}

.change-files__source { --target-size: 32px; padding-inline: var(--space-2); }
.change-files__source[aria-pressed="true"] { background: var(--color-main-lighter); color: var(--color-main-darker); }

.change-file {
  min-inline-size: 0;
  padding: var(--space-3) var(--space-4);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  background: var(--color-surface-raised);
  overflow-wrap: anywhere;
}

.change-file__source {
  margin: 0;
  font-size: var(--text-xs);
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.notice { padding: var(--space-2) var(--space-3); border-radius: var(--radius); background: var(--color-main-lighter); color: var(--color-main-darker); }
</style>
