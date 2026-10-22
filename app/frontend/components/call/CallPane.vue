<script setup lang="ts">
import { ref } from "vue"
import { storeToRefs } from "pinia"
import CallControls from "./CallControls.vue"
import CallHeader from "./CallHeader.vue"
import CallTiles from "./CallTiles.vue"
import { clampPaneWidth, PANE_WIDTH, parsePaneWidth } from "../../composables/callState.ts"
import { readStored, writeStored } from "../../composables/storage.ts"
import { useCallStore } from "../../stores/call.ts"
import { t } from "../../i18n/index.ts"

// The expanded call on wide screens: a pane right of the content. Its left
// edge is a splitter, dragged or moved with the arrow keys; the width is
// remembered in this browser.
const WIDTH_KEY = "goalner.callPaneWidth"
const { projectTitle } = storeToRefs(useCallStore())
const width = ref(parsePaneWidth(readStored(WIDTH_KEY)))
let drag: { pointerId: number; startX: number; startWidth: number } | null = null

function resize(value: number) {
  width.value = clampPaneWidth(value)
  writeStored(WIDTH_KEY, String(width.value))
}

// The pane is on the right, so moving its edge to the left widens it.
function onKey(event: KeyboardEvent) {
  const steps: Record<string, number> = {
    ArrowLeft: width.value + PANE_WIDTH.step,
    ArrowRight: width.value - PANE_WIDTH.step,
    Home: PANE_WIDTH.min,
    End: PANE_WIDTH.max,
  }
  const next = steps[event.key]
  if (next === undefined) return
  event.preventDefault()
  resize(next)
}

function onPointerDown(event: PointerEvent) {
  if (event.button !== 0) return
  const splitter = event.currentTarget as HTMLElement
  splitter.setPointerCapture(event.pointerId)
  drag = { pointerId: event.pointerId, startX: event.clientX, startWidth: width.value }
  event.preventDefault()
}

function onPointerMove(event: PointerEvent) {
  if (drag?.pointerId !== event.pointerId) return
  width.value = clampPaneWidth(drag.startWidth + drag.startX - event.clientX)
}

function onPointerEnd(event: PointerEvent) {
  if (drag?.pointerId !== event.pointerId) return
  drag = null
  resize(width.value)
}
</script>

<template>
  <aside class="call-pane" :style="{ inlineSize: `${width}px` }" :aria-label="t('call.callIn', { project: projectTitle })">
    <div
      class="call-pane__splitter"
      role="separator"
      tabindex="0"
      aria-orientation="vertical"
      :aria-label="t('call.resize')"
      :aria-valuemin="PANE_WIDTH.min"
      :aria-valuemax="PANE_WIDTH.max"
      :aria-valuenow="width"
      @keydown="onKey"
      @pointerdown="onPointerDown"
      @pointermove="onPointerMove"
      @pointerup="onPointerEnd"
      @pointercancel="onPointerEnd"
    />
    <CallHeader />
    <CallTiles />
    <CallControls />
  </aside>
</template>

<style scoped>
.call-pane {
  position: sticky;
  top: 0;
  display: grid;
  grid-template-rows: auto minmax(0, 1fr) auto;
  gap: var(--space-3);
  block-size: 100dvh;
  padding: var(--space-3) var(--space-3) var(--space-4) var(--space-4);
  background: var(--color-nav-bg);
  color: var(--color-nav-text);
}

.call-pane__splitter {
  position: absolute;
  inset: 0 auto 0 0;
  z-index: 1;
  inline-size: 8px;
  cursor: col-resize;
  touch-action: none;

  &::after {
    content: "";
    position: absolute;
    inset: 0 auto 0 0;
    inline-size: 2px;
    background: var(--color-nav-raised);
    transition: background 150ms ease;
  }

  &:hover::after, &:focus-visible::after { inline-size: 3px; background: var(--color-main-light); }
  &:focus-visible { outline: none; }
}

@media (prefers-reduced-motion: reduce) {
  .call-pane__splitter::after { transition: none; }
}
</style>
