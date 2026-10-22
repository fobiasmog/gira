<script setup lang="ts">
import { onBeforeUnmount, ref, watch } from "vue"
import type { Track } from "livekit-client"
import AppIcon from "../ui/AppIcon.vue"
import UserAvatar from "../UserAvatar.vue"
import type { CallParticipant } from "../../stores/call.ts"
import { t } from "../../i18n/index.ts"

// One participant: their video while the camera is on, their avatar
// otherwise. The track is attached to this tile's own <video>, so no HTML is
// generated; the member's own video is mirrored.
const props = defineProps<{ participant: CallParticipant }>()
const video = ref<HTMLVideoElement>()
let attached: Track | null = null

function attach(track: Track | null) {
  if (attached === track) return
  if (attached && video.value) attached.detach(video.value)
  attached = null
  if (track && video.value) {
    track.attach(video.value)
    attached = track
  }
}

watch([() => props.participant.videoTrack, video], ([track]) => attach(track), { immediate: true, flush: "post" })
onBeforeUnmount(() => attach(null))
</script>

<template>
  <figure
    class="tile"
    :class="{ 'tile--speaking': participant.speaking }"
    :data-identity="participant.identity"
  >
    <video
      v-show="participant.videoTrack"
      ref="video"
      class="tile__video"
      :class="{ 'tile__video--mirrored': participant.local }"
      playsinline
      muted
      autoplay
    />
    <div v-if="!participant.videoTrack" class="tile__avatar">
      <UserAvatar :user="{ name: participant.name, avatar_url: participant.avatarUrl }" :size="64" />
    </div>
    <figcaption class="tile__caption">
      <span class="tile__name ellipsis">{{ participant.local ? t("call.you") : participant.name }}</span>
      <span v-if="!participant.micOn" class="tile__muted" :title="t('call.micOff')">
        <AppIcon name="mic_off" :size="16" /><span class="visually-hidden">{{ t("call.micOff") }}</span>
      </span>
    </figcaption>
  </figure>
</template>

<style scoped>
.tile {
  position: relative;
  display: grid;
  aspect-ratio: 16 / 9;
  overflow: hidden;
  border-radius: var(--radius);
  background: var(--color-nav-raised);
  outline: 3px solid transparent;
  outline-offset: -3px;
  transition: outline-color 150ms ease;
}

/* The highlight while the participant speaks. */
.tile--speaking { outline-color: var(--color-main-light); }

.tile__video {
  inline-size: 100%;
  block-size: 100%;
  object-fit: cover;
}

.tile__video--mirrored { transform: scaleX(-1); }

.tile__avatar { display: grid; place-items: center; }

.tile__caption {
  position: absolute;
  inset: auto var(--space-2) var(--space-2);
  display: flex;
  align-items: center;
  gap: var(--space-1);
  max-inline-size: calc(100% - 2 * var(--space-2));
  justify-self: start;
  padding: 2px var(--space-2);
  border-radius: var(--radius-sm);
  background: rgb(43 29 63 / 0.75);
  color: var(--color-nav-strong);
  font-size: var(--text-xs);
}

.tile__muted { display: inline-flex; color: var(--color-accent); }

@media (prefers-reduced-motion: reduce) {
  .tile { transition: none; }
}
</style>
