<script setup lang="ts">
import { storeToRefs } from "pinia"
import { useCallStore, type RemoteAudio } from "../../stores/call.ts"

// The other participants' sound, on <audio> elements of its own. Mounted for
// the whole call, because the tiles unmount in the bar and tab views.
const { remoteAudio } = storeToRefs(useCallStore())
const elements = new Map<string, HTMLAudioElement>()

function bind(audio: RemoteAudio, element: unknown) {
  const previous = elements.get(audio.sid)
  if (element instanceof HTMLAudioElement) {
    if (previous === element) return
    audio.track.attach(element)
    elements.set(audio.sid, element)
  } else if (previous) {
    audio.track.detach(previous)
    elements.delete(audio.sid)
  }
}
</script>

<template>
  <div hidden>
    <audio v-for="audio in remoteAudio" :key="audio.sid" :ref="(element) => bind(audio, element)" :data-track="audio.sid" />
  </div>
</template>
