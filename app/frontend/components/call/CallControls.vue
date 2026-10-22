<script setup lang="ts">
import { computed } from "vue"
import { storeToRefs } from "pinia"
import AppIcon, { type IconName } from "../ui/AppIcon.vue"
import AppMenu from "../ui/AppMenu.vue"
import { useCallStore, type DeviceKind } from "../../stores/call.ts"
import { t } from "../../i18n/index.ts"

// Microphone and camera toggles, device choice and Leave. The compact form,
// for the call bar, leaves out device choice and the notices.
defineProps<{ compact?: boolean }>()
const call = useCallStore()
const { micOn, camOn, devices, activeDevices, audioBlocked, notices } = storeToRefs(call)

const toggles = computed<{ kind: DeviceKind; on: boolean; icon: IconName; name: string; title: string; menu: string; toggle: () => void }[]>(() => [
  {
    kind: "audioinput", on: micOn.value, icon: micOn.value ? "mic" : "mic_off", name: t("call.microphone"),
    title: micOn.value ? t("call.turnMicOff") : t("call.turnMicOn"), menu: t("call.chooseMicrophone"), toggle: call.toggleMic,
  },
  {
    kind: "videoinput", on: camOn.value, icon: camOn.value ? "videocam" : "videocam_off", name: t("call.camera"),
    title: camOn.value ? t("call.turnCamOff") : t("call.turnCamOn"), menu: t("call.chooseCamera"), toggle: call.toggleCam,
  },
])

function choose(kind: DeviceKind, deviceId: string, close: () => void) {
  close()
  if (deviceId !== activeDevices.value[kind]) void call.switchDevice(kind, deviceId)
}
</script>

<template>
  <div class="call-controls" :class="{ 'call-controls--compact': compact }">
    <template v-if="!compact">
      <p v-for="notice in notices" :key="notice" class="call-controls__notice" role="status">{{ notice }}</p>
      <button v-if="audioBlocked" type="button" class="button" @click="call.startAudio()">
        <AppIcon name="volume_up" :size="20" />{{ t("call.enableSound") }}
      </button>
    </template>

    <div class="call-controls__row">
      <span v-for="device in toggles" :key="device.kind" class="call-controls__device">
        <button
          type="button"
          class="call-toggle"
          :class="{ 'call-toggle--off': !device.on }"
          :aria-pressed="device.on"
          :title="device.title"
          @click="device.toggle()"
        >
          <AppIcon :name="device.icon" :size="20" /><span class="visually-hidden">{{ device.name }}</span>
        </button>
        <AppMenu v-if="!compact" :label="device.menu">
          <template #trigger="{ id, expanded }">
            <button
              type="button"
              class="call-toggle call-toggle--menu"
              :popovertarget="id"
              :aria-expanded="expanded"
              :aria-label="device.menu"
              :title="device.menu"
              @click="call.refreshDevices()"
            >
              <AppIcon name="keyboard_arrow_down" :size="18" />
            </button>
          </template>
          <template #default="{ close }">
            <button
              v-for="option in devices[device.kind]"
              :key="option.deviceId"
              type="button"
              class="menu__item"
              :aria-current="option.deviceId === activeDevices[device.kind] ? 'true' : undefined"
              @click="choose(device.kind, option.deviceId, close)"
            >
              <AppIcon :name="option.deviceId === activeDevices[device.kind] ? 'check_circle' : 'radio_button_unchecked'" :size="18" />
              <span class="ellipsis">{{ option.label }}</span>
            </button>
            <p v-if="!devices[device.kind].length" class="call-controls__empty">{{ t("call.noDevices") }}</p>
          </template>
        </AppMenu>
      </span>

      <button type="button" class="call-leave" :aria-label="compact ? t('call.leave') : undefined" :title="compact ? t('call.leave') : undefined" @click="call.leave()">
        <AppIcon name="call_end" :size="20" /><span v-if="!compact">{{ t("call.leave") }}</span>
      </button>
    </div>
  </div>
</template>

<style scoped>
.call-controls { display: grid; gap: var(--space-2); }

.call-controls__notice {
  padding: var(--space-2) var(--space-3);
  border-radius: var(--radius);
  background: var(--color-nav-active);
  color: var(--color-nav-strong);
  font-size: var(--text-sm);
}

.call-controls__row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: center;
  gap: var(--space-2);
}

.call-controls--compact .call-controls__row { flex-wrap: nowrap; }

.call-controls__device { display: inline-flex; }

.call-toggle {
  display: inline-grid;
  place-items: center;
  min-inline-size: 44px;
  block-size: 40px;
  padding: 0 var(--space-2);
  border: none;
  border-radius: var(--radius);
  background: var(--color-nav-active);
  color: var(--color-nav-strong);

  &:hover { background: var(--color-main-dark); }
  &:focus-visible { outline-color: var(--color-nav-text); }
}

.call-controls__device:has(.call-toggle--menu) > .call-toggle:first-child { border-start-end-radius: 0; border-end-end-radius: 0; }

.call-toggle--menu {
  min-inline-size: 28px;
  padding: 0;
  border-start-start-radius: 0;
  border-end-start-radius: 0;
  border-inline-start: 1px solid var(--color-nav-raised);
}

/* Off is the state to notice: a light button with the crossed-out icon. */
.call-toggle--off {
  background: var(--color-nav-text);
  color: var(--color-nav-bg);

  &:hover { background: var(--color-nav-strong); }
}

.call-leave {
  display: inline-flex;
  align-items: center;
  gap: var(--space-2);
  block-size: 40px;
  padding: 0 var(--space-4);
  border: none;
  border-radius: var(--radius);
  background: var(--color-danger);
  color: #fff;
  font-size: var(--text-sm);
  font-weight: 500;

  &:hover { background: #8c1d18; }
  &:focus-visible { outline-color: var(--color-nav-text); }

  .call-controls--compact & { padding: 0 var(--space-3); }
}

.call-controls__empty { padding: var(--space-2) var(--space-3); color: var(--color-muted); font-size: var(--text-sm); }
</style>
