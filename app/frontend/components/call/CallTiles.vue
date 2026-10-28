<script setup lang="ts">
import { storeToRefs } from "pinia"
import CallTile from "./CallTile.vue"
import { useCallStore } from "../../stores/call.ts"
import { t } from "../../i18n/index.ts"

// The participants of the call, own tile last. Tiles that do not fit scroll.
const { participants } = storeToRefs(useCallStore())
</script>

<template>
  <ul role="list" class="tiles" :aria-label="t('call.participants')">
    <li v-for="participant in participants" :key="participant.identity">
      <CallTile :participant="participant" />
    </li>
  </ul>
</template>

<style scoped>
.tiles {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(min(100%, 220px), 1fr));
  align-content: start;
  gap: var(--space-2);
  min-block-size: 0;
  overflow: hidden auto;
}
</style>
