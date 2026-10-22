<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue"
import AppIcon from "../ui/AppIcon.vue"
import ConfirmDialog from "../ui/ConfirmDialog.vue"
import UserAvatar from "../UserAvatar.vue"
import { callApi } from "../../api/call.ts"
import type { CallStatus, Id } from "../../api/types.ts"
import { useCallStore } from "../../stores/call.ts"
import { t, tc } from "../../i18n/index.ts"

// The board header's call control (spec team-call, "Call indicator on the
// board"): Start call, Join call with who is in it, or In call. The
// participants are polled while the page is visible and the member is not in
// this call; test builds poll every second so system tests need not wait.
const POLL_MS = import.meta.env.MODE === "test" ? 1000 : 20_000
const MAX_AVATARS = 3

const props = defineProps<{ projectId: Id; projectTitle: string }>()
const call = useCallStore()
const state = ref<CallStatus | null>(null)
const confirming = ref(false)
const inThisCall = computed(() => call.inCallOf(props.projectId))
const participants = computed(() => state.value?.participants ?? [])
const names = computed(() => t("call.inCallNow", { names: participants.value.map((p) => p.name).join(", ") }))
let timer: ReturnType<typeof setTimeout> | undefined

async function refresh() {
  const id = props.projectId
  try {
    const result = await callApi.getCall(id)
    if (id === props.projectId) state.value = result
  } catch {
    // Keeps what it showed; the next poll tries again.
  }
}

function poll() {
  clearTimeout(timer)
  if (document.visibilityState !== "visible" || inThisCall.value) return
  timer = setTimeout(async () => {
    await refresh()
    poll()
  }, POLL_MS)
}

async function restart() {
  await refresh()
  poll()
}

function onVisibilityChange() {
  if (document.visibilityState === "visible") void restart()
  else clearTimeout(timer)
}

watch(() => props.projectId, () => {
  state.value = null
  void restart()
})
watch(inThisCall, () => void restart())
onMounted(() => {
  document.addEventListener("visibilitychange", onVisibilityChange)
  void restart()
})
onBeforeUnmount(() => {
  clearTimeout(timer)
  document.removeEventListener("visibilitychange", onVisibilityChange)
})

function join() {
  void call.join(props.projectId, props.projectTitle)
}

function activate() {
  if (inThisCall.value) call.setView("expand")
  else if (call.active) confirming.value = true
  else join()
}
</script>

<template>
  <template v-if="state?.available">
    <button v-if="inThisCall" type="button" class="button call-button call-button--in" @click="activate">
      <AppIcon name="call" :size="20" />{{ t("call.inCall") }}
    </button>
    <button v-else-if="participants.length" type="button" class="button call-button" :title="names" @click="activate">
      <AppIcon name="call" :size="20" />{{ t("call.join") }}
      <span class="call-button__avatars" aria-hidden="true">
        <UserAvatar v-for="person in participants.slice(0, MAX_AVATARS)" :key="person.id" :user="person" :size="22" />
      </span>
      <span aria-hidden="true" class="call-button__count">{{ participants.length }}</span>
      <span class="visually-hidden">{{ tc("call.participantCount", participants.length) }}. {{ names }}</span>
    </button>
    <button v-else type="button" class="button button--secondary call-button" @click="activate">
      <AppIcon name="call" :size="20" />{{ t("call.start") }}
    </button>
    <ConfirmDialog
      v-model:open="confirming"
      :title="t('call.switchTitle')"
      :message="t('call.switchMessage', { current: call.projectTitle, next: projectTitle })"
      :confirm-label="t('call.switchConfirm')"
      :on-confirm="join"
    />
  </template>
</template>

<style scoped>
.call-button__avatars { display: inline-flex; }

.call-button__avatars > * {
  border: 2px solid var(--color-primary);
  box-sizing: content-box;

  & + * { margin-inline-start: -8px; }
}

.call-button__count { font-variant-numeric: tabular-nums; }

.call-button--in { background: var(--color-success); }
.call-button--in:hover:not(:disabled) { background: #17633a; }
</style>
