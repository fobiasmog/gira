<script setup lang="ts">
import { t } from "../../i18n/index.ts"

// A change waiting for people (spec changes, "Waiting for people"): a dot,
// named "Waiting for you" for assistive technology and in its tooltip.
</script>

<template>
  <span class="waiting-marker" :title="t('changes.waiting')">
    <span class="waiting-marker__dot" aria-hidden="true" />
    <span class="visually-hidden">{{ t("changes.waiting") }}</span>
  </span>
</template>

<style scoped>
.waiting-marker { display: inline-flex; flex: none; align-items: center; }

.waiting-marker__dot {
  inline-size: 8px;
  block-size: 8px;
  border-radius: 50%;
  background: var(--tone-3-text);
}
</style>
