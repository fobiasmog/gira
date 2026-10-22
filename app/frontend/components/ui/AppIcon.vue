<script lang="ts">
export type IconName =
  | "add" | "add_circle" | "alarm_add" | "archive" | "attach_file" | "calendar_today" | "call"
  | "call_end" | "chat_bubble" | "check_box" | "check_box_outline_blank" | "check_circle"
  | "check_circle_filled" | "checklist" | "chevron_left" | "chevron_right" | "close"
  | "close_fullscreen" | "code" | "code_blocks" | "delete" | "description" | "drag_indicator" | "edit"
  | "expand_more" | "flag" | "folder_open" | "format_bold" | "format_h1" | "format_h2" | "format_h3"
  | "format_italic" | "format_list_bulleted" | "format_list_numbered" | "format_quote"
  | "format_strikethrough" | "group" | "home" | "inbox" | "keyboard_arrow_down" | "link"
  | "local_fire_department" | "local_fire_department_filled" | "logout" | "mail" | "menu" | "mic"
  | "mic_off" | "more_vert" | "open_in_full" | "person" | "radio_button_unchecked" | "redo"
  | "restore_from_trash" | "self_improvement" | "settings" | "sprint" | "thumb_up" | "undo"
  | "videocam" | "videocam_off" | "view_kanban" | "view_list" | "volume_up"
</script>

<script setup lang="ts">
import sprite from "../../assets/icons.svg?no-inline"

// Decorative by default: give the surrounding control the accessible name.
withDefaults(defineProps<{ name: IconName; size?: number }>(), { size: 24 })
</script>

<template>
  <svg class="icon" :width="size" :height="size" aria-hidden="true" focusable="false">
    <use :href="`${sprite}#${name}`" />
  </svg>
</template>

<style scoped>
.icon {
  flex: none;
  fill: currentColor;
}
</style>
