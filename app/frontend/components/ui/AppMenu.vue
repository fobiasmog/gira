<script setup lang="ts">
import { computed, ref, useId } from "vue"

// A popover anchored to its trigger. The browser handles light dismiss
// (outside click, Escape) and keeps it in the top layer. Positioned with CSS
// anchor positioning where supported, otherwise from the trigger's rectangle
// when it opens.
const props = withDefaults(defineProps<{ label: string; align?: "start" | "end" }>(), { align: "start" })
defineSlots<{
  trigger(props: { id: string; expanded: boolean }): unknown
  default(props: { close: () => void }): unknown
}>()

const id = useId()
const anchorName = `--menu-${id.replace(/[^a-zA-Z0-9-]/g, "")}`
const popover = ref<HTMLElement>()
const expanded = ref(false)
const fallbackPosition = ref<Record<string, string>>({})
const supportsAnchor = typeof CSS !== "undefined" && CSS.supports("anchor-name: --a")

const popoverStyle = computed(() => (supportsAnchor ? { positionAnchor: anchorName } : fallbackPosition.value))

function trigger(): HTMLElement | null {
  return document.querySelector(`[popovertarget="${CSS.escape(id)}"]`)
}

function place() {
  const anchor = trigger()?.getBoundingClientRect()
  const menu = popover.value?.getBoundingClientRect()
  if (!anchor || !menu) return
  const gap = 4
  const top = anchor.bottom + gap + menu.height > innerHeight ? Math.max(gap, anchor.top - gap - menu.height) : anchor.bottom + gap
  const preferred = props.align === "end" ? anchor.right - menu.width : anchor.left
  const left = Math.min(Math.max(gap, preferred), innerWidth - menu.width - gap)
  fallbackPosition.value = { top: `${top}px`, left: `${left}px` }
}

function onToggle(event: Event) {
  expanded.value = (event as ToggleEvent).newState === "open"
  if (expanded.value && !supportsAnchor) place()
}

function close() {
  popover.value?.hidePopover()
}

defineExpose({ close })
</script>

<template>
  <span class="menu-anchor" :style="supportsAnchor ? { anchorName } : undefined">
    <slot name="trigger" :id="id" :expanded="expanded" />
  </span>
  <div
    :id="id"
    ref="popover"
    popover="auto"
    class="menu"
    :class="[`menu--${align}`, { 'menu--anchored': supportsAnchor }]"
    :style="popoverStyle"
    role="group"
    :aria-label="label"
    @toggle="onToggle"
  >
    <slot :close="close" />
  </div>
</template>

<style scoped>
.menu-anchor { display: inline-flex; }

.menu {
  position: fixed;
  inset: auto;
  min-inline-size: 180px;
  max-inline-size: min(320px, 100vw - 16px);
  max-block-size: min(420px, 100dvh - 16px);
  overflow: auto;
  padding: var(--space-1) 0;
  border-radius: var(--radius);
  background: var(--color-surface);
  box-shadow: var(--shadow-popover);
}

.menu--anchored {
  inset: auto;
  top: anchor(bottom);
  margin-block-start: 4px;
  position-try-fallbacks: flip-block, flip-inline;

  &.menu--start { left: anchor(left); }
  &.menu--end { right: anchor(right); }
}
</style>
