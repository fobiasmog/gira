<script setup lang="ts" generic="T extends string | number | null">
import { computed } from "vue"
import AppMenu from "./AppMenu.vue"
import AppIcon from "./AppIcon.vue"
import { t } from "../../i18n/index.ts"

// A field whose value is picked from a list: the trigger shows the field's
// name and current value, the popover lists the choices.
export interface Choice<V> { value: V; label: string }

const props = defineProps<{ label: string; choices: Choice<T>[]; selected: T; disabled?: boolean }>()
const emit = defineEmits<{ choose: [value: T] }>()
defineSlots<{ default?(props: { close: () => void }): unknown; value?(): unknown }>()

const current = computed(() => props.choices.find((choice) => choice.value === props.selected)?.label ?? "")
</script>

<template>
  <AppMenu :label="label">
    <template #trigger="{ id, expanded }">
      <button
        type="button"
        class="choice-trigger"
        :popovertarget="id"
        :aria-expanded="expanded"
        :disabled="disabled"
        :aria-label="`${t('task.change', { field: label })}: ${current}`"
      >
        <span class="choice-trigger__value ellipsis"><slot name="value">{{ current }}</slot></span>
        <AppIcon name="expand_more" :size="20" />
      </button>
    </template>
    <template #default="{ close }">
      <button
        v-for="choice in choices"
        :key="String(choice.value)"
        type="button"
        class="menu__item"
        :aria-current="choice.value === selected ? 'true' : undefined"
        @click="close(); choice.value !== selected && emit('choose', choice.value)"
      >
        <AppIcon :name="choice.value === selected ? 'check_circle' : 'radio_button_unchecked'" :size="18" />
        <span class="ellipsis">{{ choice.label }}</span>
      </button>
      <slot :close="close" />
    </template>
  </AppMenu>
</template>

<style scoped>
/* The trigger shows the current value as a full-width button. */
.choice-trigger {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-2);
  inline-size: 100%;
  min-block-size: var(--target-size);
  padding: var(--space-1) var(--space-1) var(--space-1) var(--space-3);
  border: 1px solid var(--color-border);
  border-radius: var(--radius);
  background: var(--color-surface);
  color: var(--color-text);
  font-size: var(--text-sm);
  text-align: start;

  &:hover:not(:disabled) { border-color: var(--color-main-light); background: var(--color-surface-raised); }
  &[aria-expanded="true"] { border-color: var(--color-primary); }
  &:disabled { color: var(--color-muted); }
  & > .icon { color: var(--color-muted); }
}

.choice-trigger__value { min-inline-size: 0; }
</style>
